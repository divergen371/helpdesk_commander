defmodule HelpdeskCommanderWeb.AttachmentLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
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
    assert has_element?(view, "#ticket-attachments", "検査中")

    [attachment] = Ash.read!(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
    assert attachment.filename == "note.txt"
    assert attachment.scan_status == "pending"
    assert_enqueued(worker: HelpdeskCommander.Workers.ScanAttachmentWorker, args: %{attachment_id: attachment.id})

    view
    |> element("#ticket-attachment-#{attachment.id} button", "削除")
    |> render_click()

    refute has_element?(view, "#ticket-attachment-#{attachment.id}")
    assert {:ok, []} = Ash.read(TicketAttachment, domain: Helpdesk, tenant: ticket.company_id)
  end

  test "shows scanner metadata on the attachment", %{conn: conn, ticket: ticket, admin: admin} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 0"]})

    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_version_command,
      {"sh", ["-c", "echo 'ClamAV 1.4.1/27480/Wed Nov  5 08:12:34 2026'"]}
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, :attachment_scan_version_command) end)

    {:ok, attachment} =
      Attachments.ingest(ticket, admin, %Plug.Upload{
        path: tmp_file("report.txt", "hello"),
        filename: "report.txt",
        content_type: "text/plain"
      })

    {:ok, attachment} = Attachments.scan_attachment(attachment)

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#ticket-attachment-scan-#{attachment.id}")
    assert render(view) =~ "ClamAV 1.4.1"
    assert render(view) =~ "2026-11-05 08:12 UTC"
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

    {:ok, infected} =
      Attachments.ingest(
        ticket,
        admin,
        %Plug.Upload{path: tmp_file("bad.txt", "virus"), filename: "bad.txt", content_type: "text/plain"}
      )

    {:ok, _infected} = Attachments.scan_attachment(infected)

    Application.delete_env(:helpdesk_commander, :attachment_scan_command)

    {:ok, clean} =
      Attachments.ingest(
        ticket,
        admin,
        %Plug.Upload{path: tmp_file("good.txt", "hello"), filename: "good.txt", content_type: "text/plain"}
      )

    {:ok, _clean} = Attachments.scan_attachment(clean)

    conn = log_in(conn, external)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#ticket-attachments", "good.txt")
    refute has_element?(view, "#ticket-attachments", "bad.txt")
  end

  test "admin can rescan a failed attachment", %{conn: conn, ticket: ticket, admin: admin} do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "exit 2"]})

    {:ok, attachment} =
      Attachments.ingest(ticket, admin, %Plug.Upload{
        path: tmp_file("broken.txt", "hello"),
        filename: "broken.txt",
        content_type: "text/plain"
      })

    {:ok, attachment} = Attachments.scan_attachment(attachment)
    assert attachment.scan_status == "failed"

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#ticket-attachment-#{attachment.id} button", "再スキャン")

    view
    |> element("#ticket-attachment-#{attachment.id} button", "再スキャン")
    |> render_click()

    assert render(view) =~ "再スキャンを開始しました"
    assert Ash.get!(TicketAttachment, attachment.id, domain: Helpdesk, authorize?: false).scan_status == "pending"
  end

  test "admin can override an infected attachment with a required reason and see the audit event", %{
    conn: conn,
    company: company,
    ticket: ticket,
    admin: admin
  } do
    Application.put_env(:helpdesk_commander, :attachment_scan_command, {"sh", ["-c", "echo 'EICAR'; exit 1"]})

    {:ok, attachment} =
      Attachments.ingest(ticket, admin, %Plug.Upload{
        path: tmp_file("flagged.txt", "hello"),
        filename: "flagged.txt",
        content_type: "text/plain"
      })

    {:ok, attachment} = Attachments.scan_attachment(attachment)
    assert attachment.scan_status == "infected"

    member = create_user!(company.id, "user")
    member_conn = log_in(conn, member)
    {:ok, member_view, _html} = live(member_conn, ~p"/tickets/#{ticket.public_id}")
    refute has_element?(member_view, "#override-attachment-form-#{attachment.id}")

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#override-attachment-form-#{attachment.id}")

    view
    |> form("#override-attachment-form-#{attachment.id}", %{"override" => %{"reason" => "   "}})
    |> render_submit()

    assert render(view) =~ "解除理由を入力してください"
    assert Ash.get!(TicketAttachment, attachment.id, domain: Helpdesk, authorize?: false).scan_status == "infected"

    view
    |> form("#override-attachment-form-#{attachment.id}", %{
      "override" => %{"reason" => "社内ツールの誤検知を確認"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "誤検知として隔離を解除しました"
    assert html =~ "感染判定の誤検知解除"
    assert html =~ "社内ツールの誤検知を確認"
    assert Ash.get!(TicketAttachment, attachment.id, domain: Helpdesk, authorize?: false).scan_status == "clean"
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
