defmodule HelpdeskCommanderWeb.AttachmentLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketAttachment

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_command) end)

    %{company: company, admin: admin, ticket: ticket}
  end

  test "uploads, lists, and deletes an attachment", %{conn: conn, ticket: ticket, admin: admin} do
    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#attachment-form")
    assert has_element?(view, "#ticket-attachments-empty")

    upload =
      file_input(view, "#attachment-form", :attachment, [
        %{name: "note.txt", content: "hello", type: "text/plain", size: 5}
      ])

    render_upload(upload, "note.txt")
    render_submit(view, "upload_attachment", %{})

    assert has_element?(view, "#ticket-attachments", "note.txt")
    assert has_element?(view, "#ticket-attachments", "未検査")

    [attachment] = Ash.read!(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
    assert attachment.filename == "note.txt"
    assert attachment.scan_status == "skipped"

    view
    |> element("#ticket-attachment-#{attachment.id} button", "削除")
    |> render_click()

    refute has_element?(view, "#ticket-attachment-#{attachment.id}")
    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  test "external requester sees only downloadable attachments", %{
    conn: conn,
    company: company,
    admin: admin
  } do
    external = create_user!(company.id, "customer")
    product = create_product!(company)
    ticket = create_ticket!(product, external)

    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 1"]})

    {:ok, _infected} =
      Helpdesk.Attachments.ingest(
        ticket,
        admin,
        %Plug.Upload{path: tmp_file("bad.txt", "virus"), filename: "bad.txt", content_type: "text/plain"}
      )

    Application.delete_env(:helpdesk_commander, :attachment_scan_command)

    {:ok, _clean} =
      Helpdesk.Attachments.ingest(
        ticket,
        admin,
        %Plug.Upload{path: tmp_file("good.txt", "hello"), filename: "good.txt", content_type: "text/plain"}
      )

    conn = log_in(conn, external)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#ticket-attachments", "good.txt")
    refute has_element?(view, "#ticket-attachments", "bad.txt")
  end

  defp tmp_file(name, content) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Attachment UI ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "attachment-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Attachment UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Attachment UI Product #{System.unique_integer([:positive])}",
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
