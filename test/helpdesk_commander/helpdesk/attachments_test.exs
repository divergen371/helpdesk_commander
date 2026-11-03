defmodule HelpdeskCommander.Helpdesk.AttachmentsTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.Storage
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_command) end)

    %{company: company, admin: admin, product: product, ticket: ticket}
  end

  test "stores a clean file and moves it to the clean directory", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("report.txt", "hello", "text/plain"))

    assert attachment.scan_status == "clean"
    assert attachment.filename == "report.txt"
    assert attachment.byte_size == 5
    assert attachment.sha256 == sha256("hello")

    assert File.exists?(Storage.path(:clean, attachment.storage_key))
    refute File.exists?(Storage.path(:quarantine, attachment.storage_key))
    assert {:ok, path} = Attachments.download_path(attachment)
    assert File.read!(path) == "hello"
  end

  test "keeps an infected file in quarantine and blocks download", %{
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("bad.txt", "virus", "text/plain"))

    assert attachment.scan_status == "infected"
    refute File.exists?(Storage.path(:clean, attachment.storage_key))
    assert File.exists?(Storage.path(:quarantine, attachment.storage_key))
    assert {:error, :not_ready} = Attachments.download_path(attachment)
  end

  test "marks files as skipped when no scanner is configured", %{
    ticket: ticket,
    admin: admin
  } do
    assert {:ok, attachment} =
             Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

    assert attachment.scan_status == "skipped"
    assert File.exists?(Storage.path(:clean, attachment.storage_key))
    assert Attachments.downloadable?(attachment)
  end

  test "rejects disallowed extensions and MIME types", %{ticket: ticket, admin: admin} do
    assert {:error, :extension_not_allowed} =
             Attachments.ingest(ticket, admin, upload("script.exe", "MZ", "application/octet-stream"))

    assert {:error, :content_type_not_allowed} =
             Attachments.ingest(ticket, admin, upload("image.png", "not-an-image", "text/plain"))

    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  test "limits downloads to users who can see the ticket", %{
    company: company,
    ticket: ticket,
    admin: admin
  } do
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))

    assert {:ok, fetched} = Attachments.fetch_for_download(attachment.id, admin)
    assert fetched.id == attachment.id

    other_company_user = create_user_in_new_company!()
    assert {:error, :not_found} = Attachments.fetch_for_download(attachment.id, other_company_user)

    external_requester = create_user!(company.id, "customer")
    external_ticket = create_ticket!(create_product!(company), external_requester)

    {:ok, external_attachment} =
      Attachments.ingest(external_ticket, external_requester, upload("photo.png", "png", "image/png"))

    assert {:ok, _attachment} = Attachments.fetch_for_download(external_attachment.id, external_requester)

    other_external = create_user!(company.id, "customer")
    assert {:error, :forbidden} = Attachments.fetch_for_download(external_attachment.id, other_external)
  end

  test "deletes the record and the stored file", %{ticket: ticket, admin: admin} do
    {:ok, attachment} = Attachments.ingest(ticket, admin, upload("note.txt", "hello", "text/plain"))
    path = Storage.path(:clean, attachment.storage_key)

    assert :ok = Attachments.delete(attachment, admin)
    refute File.exists?(path)
    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  defp upload(filename, content, content_type) do
    path = Path.join(System.tmp_dir!(), "attachment-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Attachment ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_user_in_new_company! do
    company = create_company!()
    create_user!(company.id, "admin")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "attachment+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Attachment #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
