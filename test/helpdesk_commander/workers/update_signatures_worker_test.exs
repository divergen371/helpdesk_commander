defmodule HelpdeskCommander.Workers.UpdateSignaturesWorkerTest do
  use HelpdeskCommander.DataCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.Signatures
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.ClamdFakeServer
  alias HelpdeskCommander.Helpdesk.TicketAttachment
  alias HelpdeskCommander.Workers.ScanAttachmentWorker
  alias HelpdeskCommander.Workers.UpdateSignaturesWorker

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)
    attachment = clean_attachment!(ticket, admin)

    original = [
      Application.get_env(:helpdesk_commander, :attachment_signature_update_command),
      Application.get_env(:helpdesk_commander, :attachment_scan_version_command),
      Application.get_env(:helpdesk_commander, :attachment_rescan_limit),
      Application.get_env(:helpdesk_commander, :attachment_scan_clamd)
    ]

    on_exit(fn ->
      [update, version, limit, clamd] = original
      Application.put_env(:helpdesk_commander, :attachment_signature_update_command, update)
      Application.put_env(:helpdesk_commander, :attachment_scan_version_command, version)
      Application.put_env(:helpdesk_commander, :attachment_rescan_limit, limit)
      Application.put_env(:helpdesk_commander, :attachment_scan_clamd, clamd)
    end)

    %{ticket: ticket, admin: admin, attachment: attachment}
  end

  test "updates signatures, records metadata, and rescans clean attachments", %{
    attachment: attachment
  } do
    Application.put_env(:helpdesk_commander, :attachment_signature_update_command, {"sh", ["-c", "exit 0"]})

    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_version_command,
      {"sh", ["-c", "echo 'ClamAV 1.4.2/27500/Thu Nov  6 09:00:00 2026'"]}
    )

    assert :ok = perform_job(UpdateSignaturesWorker, %{})

    assert {:ok, signature} = Signatures.current()
    assert signature.status == "ok"
    assert signature.engine == "ClamAV"
    assert signature.version == "1.4.2"

    assert reload!(attachment).scan_status == "pending"
    assert_enqueued(worker: ScanAttachmentWorker, args: %{attachment_id: attachment.id})
  end

  test "records an error and does not rescan when the update fails", %{attachment: attachment} do
    Application.put_env(:helpdesk_commander, :attachment_signature_update_command, {"sh", ["-c", "exit 2"]})

    assert {:error, {:exit_status, 2, _output}} = perform_job(UpdateSignaturesWorker, %{})

    assert {:ok, signature} = Signatures.current()
    assert signature.status == "error"
    assert signature.last_error =~ "exit_status"
    assert reload!(attachment).scan_status == "clean"
  end

  test "does nothing when no update command is configured", %{attachment: attachment} do
    Application.delete_env(:helpdesk_commander, :attachment_signature_update_command)

    assert :ok = perform_job(UpdateSignaturesWorker, %{})
    assert {:ok, nil} = Signatures.current()
    assert reload!(attachment).scan_status == "clean"
  end

  test "reloads clamd signatures without an update command", %{attachment: attachment} do
    Application.delete_env(:helpdesk_commander, :attachment_signature_update_command)

    {:ok, port, _server} =
      ClamdFakeServer.start(mode: :clean, version: "ClamAV 1.4.4/27800/Sat Nov  8 00:00:00 2026")

    Application.put_env(:helpdesk_commander, :attachment_scan_clamd, host: "127.0.0.1", port: port)

    assert :ok = perform_job(UpdateSignaturesWorker, %{})

    assert {:ok, signature} = Signatures.current()
    assert signature.status == "ok"
    assert signature.engine == "ClamAV"
    assert signature.version == "1.4.4"
    assert reload!(attachment).scan_status == "pending"
  end

  test "records an error when clamd rejects the reload", %{attachment: attachment} do
    Application.delete_env(:helpdesk_commander, :attachment_signature_update_command)

    {:ok, port, _server} = ClamdFakeServer.start(reload_response: "ERROR: database problem")
    Application.put_env(:helpdesk_commander, :attachment_scan_clamd, host: "127.0.0.1", port: port)

    assert {:error, {:clamd_reload, "ERROR: database problem"}} =
             perform_job(UpdateSignaturesWorker, %{})

    assert {:ok, signature} = Signatures.current()
    assert signature.status == "error"
    assert reload!(attachment).scan_status == "clean"
  end

  defp clean_attachment!(ticket, user) do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})
    path = Path.join(System.tmp_dir!(), "update-sig-#{System.unique_integer([:positive])}")
    File.write!(path, "hello")

    {:ok, attachment} =
      Attachments.ingest(ticket, user, %Plug.Upload{
        path: path,
        filename: "note.txt",
        content_type: "text/plain"
      })

    {:ok, attachment} = Attachments.scan_attachment(attachment)
    attachment
  end

  defp reload!(attachment) do
    Ash.get!(TicketAttachment, attachment.id, domain: Helpdesk, authorize?: false)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Signature update ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Signature Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "signature+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Signature #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Signature Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
