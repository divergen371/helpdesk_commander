defmodule HelpdeskCommanderWeb.PriorityLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "a new ticket computes priority from impact and urgency", %{conn: conn} do
    company = create_company!()
    user = create_user!(company.id, "admin")
    product = create_product!(company)
    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tickets/new")

    view
    |> form("#ticket-form",
      form: %{
        "subject" => "Priority from dimensions",
        "type" => "question",
        "status" => "new",
        "impact" => "widespread",
        "urgency" => "critical",
        "product_id" => to_string(product.id),
        "requester_id" => to_string(user.id)
      }
    )
    |> render_submit()

    ticket =
      Ticket
      |> Ash.read_one!(domain: Helpdesk, tenant: company.id)

    assert ticket.priority == "p1"
    assert ticket.priority_source == "auto"
    assert ticket.impact == "widespread"
    assert ticket.urgency == "critical"
  end

  test "an admin recalculates priority from the ticket view", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: "Priority update",
        impact: "minor",
        urgency: "low",
        product_id: product.id,
        requester_id: admin.id
      })
      |> Ash.create!(domain: Helpdesk)

    assert ticket.priority == "p4"

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#ticket-priority-form")

    view
    |> form("#ticket-priority-form",
      form: %{"impact" => "widespread", "urgency" => "critical"}
    )
    |> render_submit()

    updated =
      Ticket
      |> Ash.get!(ticket.id, domain: Helpdesk, tenant: company.id)

    assert updated.priority == "p1"
    assert updated.priority_source == "auto"
    assert render(view) =~ "広範（全社・複数顧客）"
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "priority-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Priority UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority UI Product #{System.unique_integer([:positive])}",
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
