defmodule HelpdeskCommanderWeb.TicketLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query
  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketMessage

  test "tickets index renders", %{conn: conn} do
    user = create_user!()
    _ticket = create_ticket!(user)

    {:ok, view, _html} = live(conn, ~p"/tickets")

    assert has_element?(view, "#tickets")
    assert has_element?(view, "#tickets tr")
  end

  test "create ticket via new form", %{conn: conn} do
    user = create_user!()

    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    params = %{
      "subject" => "Cannot login",
      "description" => "Login fails with 500",
      "type" => "incident",
      "status" => "new",
      "priority" => "p2",
      "requester_id" => to_string(user.id)
    }

    view
    |> form("#ticket-form", form: params)
    |> render_submit()

    [created | _rest] =
      Ticket
      |> Ash.read!(domain: Helpdesk)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    assert created.subject == "Cannot login"

    {:ok, show_view, _show_html} = live(conn, ~p"/tickets/#{created.public_id}")
    assert has_element?(show_view, "#ticket-status-form")
  end

  test "update ticket status", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-status-form", form: %{"status" => "resolved", "priority" => ticket.priority})
    |> render_submit()

    updated = Ash.get!(Ticket, %{public_id: ticket.public_id}, domain: Helpdesk)
    assert updated.status == "resolved"
  end

  test "add message to ticket", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-message-form",
      form: %{
        "body" => "First response",
        "sender_id" => to_string(user.id)
      }
    )
    |> render_submit()

    messages =
      TicketMessage
      |> filter(ticket_id == ^ticket.id)
      |> Ash.read!(domain: Helpdesk)

    assert Enum.any?(messages, &(&1.body == "First response"))

    updated = Ash.get!(Ticket, %{public_id: ticket.public_id}, domain: Helpdesk)
    assert not is_nil(updated.latest_message_at)
  end

  defp create_user! do
    email = "test+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{email: email, name: "Test User"})
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Test ticket",
      description: "Test",
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
