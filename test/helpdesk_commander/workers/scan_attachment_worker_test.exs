defmodule HelpdeskCommander.Workers.ScanAttachmentWorkerTest do
  use HelpdeskCommander.DataCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo

  import Ecto.Query
  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment
  alias HelpdeskCommander.Workers.ScanAttachmentWorker

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_command) end)

    attachment = ingest_pending!(ticket, admin, "note.txt", "hello")

    %{ticket: ticket, admin: admin, attachment: attachment}
  end

  test "performs a pending scan and marks the attachment clean", %{attachment: attachment} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

    assert :ok = perform_job(ScanAttachmentWorker, %{attachment_id: attachment.id})

    reloaded = reload!(attachment)
    assert reloaded.scan_status == "clean"
    assert File.exists?(HelpdeskCommander.Attachments.Storage.path(:clean, reloaded.storage_key))
  end

  test "returns an error for failed scans so Oban retries", %{attachment: attachment} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 2"]})

    assert {:error, :scan_failed} = perform_job(ScanAttachmentWorker, %{attachment_id: attachment.id})
    assert reload!(attachment).scan_status == "failed"
  end

  test "does not rescan terminal attachments", %{attachment: attachment} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
    assert :ok = perform_job(ScanAttachmentWorker, %{attachment_id: attachment.id})

    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})
    assert :ok = perform_job(ScanAttachmentWorker, %{attachment_id: attachment.id})

    assert reload!(attachment).scan_status == "clean"
  end

  test "ignores a deleted attachment", %{attachment: attachment} do
    assert :ok = perform_job(ScanAttachmentWorker, %{attachment_id: attachment.id + 999_999})
  end

  test "enqueue is unique per attachment while a job is pending", %{attachment: attachment} do
    assert {:ok, _job} = ScanAttachmentWorker.enqueue(attachment.id)

    count =
      Oban.Job
      |> where(worker: "HelpdeskCommander.Workers.ScanAttachmentWorker")
      |> Repo.aggregate(:count)

    assert count == 1
  end

  test "backoff is exponential with a five minute cap" do
    assert ScanAttachmentWorker.backoff(%Oban.Job{attempt: 1}) == 30
    assert ScanAttachmentWorker.backoff(%Oban.Job{attempt: 2}) == 60
    assert ScanAttachmentWorker.backoff(%Oban.Job{attempt: 4}) == 240
    assert ScanAttachmentWorker.backoff(%Oban.Job{attempt: 5}) == 300
    assert ScanAttachmentWorker.backoff(%Oban.Job{attempt: 9}) == 300
  end

  defp ingest_pending!(ticket, user, filename, content) do
    path = Path.join(System.tmp_dir!(), "worker-#{System.unique_integer([:positive])}")
    File.write!(path, content)

    {:ok, attachment} =
      Attachments.ingest(ticket, user, %Plug.Upload{
        path: path,
        filename: filename,
        content_type: "text/plain"
      })

    attachment
  end

  defp reload!(attachment) do
    Ash.get!(TicketAttachment, attachment.id, domain: Helpdesk, authorize?: false)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Worker ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Worker Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "worker+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Worker #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Worker Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
