defmodule HelpdeskCommanderWeb.NotificationLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification

  test "recipient sees only their notifications", %{conn: conn} do
    recipient = create_user!("admin")
    other = create_user!("leader")
    ticket = create_ticket!(recipient)

    own = create_notification!(ticket, recipient, "自分の通知")
    _other = create_notification!(ticket, other, "他の人の通知")

    conn = log_in(conn, recipient)
    {:ok, view, _html} = live(conn, ~p"/notifications")

    assert has_element?(view, "#notifications", own.title)
    refute has_element?(view, "#notifications", "他の人の通知")
    assert has_element?(view, "h1", "通知")
  end

  test "recipient can mark a notification as read", %{conn: conn} do
    recipient = create_user!("admin")
    ticket = create_ticket!(recipient)
    notification = create_notification!(ticket, recipient, "既読にする通知")

    conn = log_in(conn, recipient)
    {:ok, view, _html} = live(conn, ~p"/notifications")

    assert has_element?(view, "span", "未読")

    view
    |> element("button[phx-click=\"mark_read\"][phx-value-id=\"#{notification.id}\"]")
    |> render_click()

    updated = Ash.get!(TicketNotification, %{id: notification.id}, domain: Helpdesk, actor: recipient)
    assert updated.read_at != nil
    refute has_element?(view, "span", "未読")
    assert has_element?(view, "p", "通知を既読にしました")
  end

  test "recipient can mark all notifications as read", %{conn: conn} do
    recipient = create_user!("admin")
    ticket = create_ticket!(recipient)
    first = create_notification!(ticket, recipient, "通知1")
    second = create_notification!(ticket, recipient, "通知2")

    conn = log_in(conn, recipient)
    {:ok, view, _html} = live(conn, ~p"/notifications")

    view
    |> element("button[phx-click=\"mark_all_read\"]")
    |> render_click()

    for notification <- [first, second] do
      updated = Ash.get!(TicketNotification, %{id: notification.id}, domain: Helpdesk, actor: recipient)
      assert updated.read_at != nil
    end

    refute has_element?(view, "span", "未読")
    assert has_element?(view, "p", "2 件の通知を既読にしました")
  end

  test "non-recipient cannot mark another user's notification as read", %{conn: conn} do
    recipient = create_user!("admin")
    other = create_user!("leader")
    ticket = create_ticket!(recipient)
    notification = create_notification!(ticket, recipient, "他人の通知")

    conn = log_in(conn, other)
    {:ok, view, _html} = live(conn, ~p"/notifications")

    log =
      capture_log(fn ->
        render_click(view, "mark_read", %{"id" => to_string(notification.id)})
      end)

    reloaded = Ash.get!(TicketNotification, %{id: notification.id}, domain: Helpdesk, actor: recipient)
    assert reloaded.read_at == nil
    assert has_element?(view, "p", "通知の更新に失敗しました")
    assert log =~ "[notification_live.index.mark_read]"
  end

  test "ticket index shows the unread notification count", %{conn: conn} do
    recipient = create_user!("admin")
    ticket = create_ticket!(recipient)
    _notification = create_notification!(ticket, recipient, "未読通知")

    conn = log_in(conn, recipient)
    {:ok, view, _html} = live(conn, ~p"/tickets")

    assert has_element?(view, "a", "通知 (1)")
  end

  test "unauthenticated user is redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/notifications")
  end

  defp create_notification!(ticket, recipient, title) do
    TicketNotification
    |> Ash.Changeset.for_create(:create, %{
      notification_type: "test",
      title: title,
      body: "通知本文",
      company_id: ticket.company_id,
      ticket_id: ticket.id,
      recipient_id: recipient.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_user!(role) do
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "notify+#{System.unique_integer([:positive])}@example.com",
      display_name: "Notify User",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Notification Test",
      description: "Notification Test",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
