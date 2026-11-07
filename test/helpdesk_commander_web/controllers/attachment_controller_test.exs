defmodule HelpdeskCommanderWeb.AttachmentControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_command) end)

    %{company: company, admin: admin, ticket: ticket}
  end

  test "downloads an attachment for an authorized user", %{conn: conn, ticket: ticket, admin: admin} do
    {:ok, attachment} = ingest!(ticket, admin, "note.txt", "hello", "text/plain")

    conn = log_in(conn, admin)
    conn = get(conn, "/attachments/#{attachment.id}")

    assert response(conn, 200) == "hello"
    [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/plain"

    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "note.txt"
  end

  test "redirects unauthenticated users", %{conn: conn, ticket: ticket, admin: admin} do
    {:ok, attachment} = ingest!(ticket, admin, "note.txt", "hello", "text/plain")

    conn = get(conn, "/attachments/#{attachment.id}")

    assert redirected_to(conn) == "/sign-in"
  end

  test "forbids external users who do not own the ticket", %{
    conn: conn,
    company: company,
    ticket: ticket,
    admin: admin
  } do
    {:ok, attachment} = ingest!(ticket, admin, "note.txt", "hello", "text/plain")
    other_external = create_user!(company.id, "customer")

    conn = log_in(conn, other_external)
    conn = get(conn, "/attachments/#{attachment.id}")

    assert response(conn, 403)
  end

  test "forbids downloading a quarantined attachment", %{conn: conn, ticket: ticket, admin: admin} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

    {:ok, attachment} = ingest!(ticket, admin, "bad.txt", "virus", "text/plain")
    assert attachment.scan_status == "infected"

    conn = log_in(conn, admin)
    conn = get(conn, "/attachments/#{attachment.id}")

    assert response(conn, 403)
  end

  test "returns not found for another company", %{conn: conn, ticket: ticket, admin: admin} do
    {:ok, attachment} = ingest!(ticket, admin, "note.txt", "hello", "text/plain")

    other_company = create_company!()
    other_admin = create_user!(other_company.id, "admin")

    conn = log_in(conn, other_admin)
    conn = get(conn, "/attachments/#{attachment.id}")

    assert response(conn, 404)
  end

  defp ingest!(ticket, user, filename, content, content_type) do
    path = Path.join(System.tmp_dir!(), "download-#{System.unique_integer([:positive])}")
    File.write!(path, content)

    with {:ok, attachment} <-
           Helpdesk.Attachments.ingest(ticket, user, %Plug.Upload{
             path: path,
             filename: filename,
             content_type: content_type
           }) do
      Helpdesk.Attachments.scan_attachment(attachment)
    end
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Attachment download ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Download Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "attachment-download+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Attachment Download #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment Download Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
