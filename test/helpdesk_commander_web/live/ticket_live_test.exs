defmodule HelpdeskCommanderWeb.TicketLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query
  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent

  test "tickets index renders", %{conn: conn} do
    user = create_user!()
    _ticket = create_ticket!(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets")

    assert has_element?(view, "#tickets")
    assert has_element?(view, "#tickets tr")
  end

  test "create ticket via new form", %{conn: conn} do
    user = create_user!()
    product = create_product!(user.company_id)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    params = %{
      "subject" => "Cannot login",
      "description" => "Login fails with 500",
      "type" => "incident",
      "status" => "new",
      "priority" => "p2",
      "product_id" => to_string(product.id),
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

  test "new ticket validates and can create a sample user", %{conn: conn} do
    user = create_user!()
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    assert has_element?(view, "button[phx-click=\"create_sample_user\"]")

    view
    |> form("#ticket-form", form: %{"subject" => ""})
    |> render_change()

    view
    |> form("#ticket-form", form: %{"subject" => ""})
    |> render_submit()

    assert has_element?(view, "#ticket-form")

    view
    |> element("button[phx-click=\"create_sample_user\"]")
    |> render_click()

    assert [_user | _rest] = Ash.read!(User, domain: Accounts)
  end

  test "update ticket status", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-status-form", form: %{"status" => "resolved", "actor_id" => to_string(user.id)})
    |> render_submit()

    updated = Ash.get!(Ticket, %{public_id: ticket.public_id}, domain: Helpdesk)
    assert updated.status == "resolved"
  end

  test "add message to ticket", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-message-form-public",
      public_message: %{
        "body" => "First response",
        "sender_id" => to_string(user.id)
      }
    )
    |> render_submit()

    conversation =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == "internal_public")
      |> Ash.read_one!(domain: Helpdesk)

    messages =
      ConversationMessage
      |> filter(conversation_id == ^conversation.id)
      |> Ash.read!(domain: Helpdesk)

    assert Enum.any?(messages, &(&1.body == "First response"))

    updated = Ash.get!(Ticket, %{public_id: ticket.public_id}, domain: Helpdesk)
    assert not is_nil(updated.latest_message_at)

    events =
      TicketEvent
      |> filter(ticket_id == ^ticket.id)
      |> Ash.read!(domain: Helpdesk)

    assert Enum.any?(events, &(&1.event_type == "message_posted" && &1.actor_id == user.id))
  end

  test "load older messages and events", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)
    public_conversation = get_conversation!(ticket, "internal_public")

    for index <- 1..21 do
      _message = create_message!(public_conversation, user, "Message #{index}")
    end

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(
             view,
             "button[phx-click=\"load_older_messages\"][phx-value-kind=\"public\"]"
           )

    assert has_element?(view, "button[phx-click=\"load_older_events\"]")

    view
    |> element("button[phx-click=\"load_older_messages\"][phx-value-kind=\"public\"]")
    |> render_click()

    view
    |> element("button[phx-click=\"load_older_events\"]")
    |> render_click()

    assert has_element?(view, "#ticket-messages-public")
  end

  test "add private message to ticket", %{conn: conn} do
    user = create_user!()
    ticket = create_ticket!(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-message-form-private",
      private_message: %{
        "body" => "Internal note",
        "sender_id" => to_string(user.id)
      }
    )
    |> render_submit()

    private_conversation = get_conversation!(ticket, "internal_private")

    messages =
      ConversationMessage
      |> filter(conversation_id == ^private_conversation.id)
      |> Ash.read!(domain: Helpdesk)

    assert Enum.any?(messages, &(&1.body == "Internal note"))
  end

  test "external user posts public message", %{conn: conn} do
    user = create_user!("customer")
    ticket = create_ticket!(user)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-message-form-public",
      public_message: %{
        "body" => "Customer message"
      }
    )
    |> render_submit()

    public_conversation = get_conversation!(ticket, "internal_public")

    messages =
      ConversationMessage
      |> filter(conversation_id == ^public_conversation.id)
      |> Ash.read!(domain: Helpdesk)

    assert Enum.any?(messages, &(&1.body == "Customer message" && &1.sender_id == user.id))
  end

  test "external user sees only own tickets in index", %{conn: conn} do
    external_user = create_user!("customer")
    internal_user = create_user!()

    own_ticket = create_ticket!(external_user)
    other_ticket = create_ticket!(internal_user)

    conn = log_in(conn, external_user)
    {:ok, view, _html} = live(conn, ~p"/tickets")

    assert has_element?(view, "td", own_ticket.public_id)
    refute has_element?(view, "td", other_ticket.public_id)
  end

  test "external user cannot view other ticket detail", %{conn: conn} do
    external_user = create_user!("customer")
    internal_user = create_user!()
    other_ticket = create_ticket!(internal_user)

    conn = log_in(conn, external_user)

    assert {:error, {:live_redirect, %{to: "/tickets"}}} =
             live(conn, ~p"/tickets/#{other_ticket.public_id}")
  end

  test "external user hides internal sections in ticket detail", %{conn: conn} do
    external_user = create_user!("customer")
    ticket = create_ticket!(external_user)

    conn = log_in(conn, external_user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    refute has_element?(view, "#ticket-status-form")
    refute has_element?(view, "#ticket-messages-private")
    refute has_element?(view, "#ticket-message-form-private")
    refute has_element?(view, "#ticket-events")
  end

  defp create_user!(role \\ "user") do
    email = "test+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
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
      subject: "Test ticket",
      description: "Test",
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

  defp get_conversation!(%Ticket{} = ticket, kind) do
    Conversation
    |> filter(ticket_id == ^ticket.id and kind == ^kind)
    |> Ash.read_one!(domain: Helpdesk)
  end

  defp create_message!(%Conversation{} = conversation, %User{} = sender, body) do
    ConversationMessage
    |> Ash.Changeset.for_create(:create, %{
      body: body,
      conversation_id: conversation.id,
      sender_id: sender.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
