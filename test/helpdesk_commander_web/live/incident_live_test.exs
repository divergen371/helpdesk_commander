defmodule HelpdeskCommanderWeb.IncidentLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Incident
  alias HelpdeskCommander.Helpdesk.IncidentEvent
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "admin promotes a ticket and records the timeline", %{conn: conn} do
    {ticket, admin} = create_ticket_with_admin!()
    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#incident-promote-form")

    view
    |> form("#incident-promote-form",
      incident: %{
        "severity" => "sev1",
        "impact_scope" => "全社",
        "announcement" => "調査中"
      }
    )
    |> render_submit()

    assert has_element?(view, "#incident-update-form")
    assert has_element?(view, "#incident-event-form")
    assert render(view) =~ "インシデント"

    incident =
      Incident
      |> filter(ticket_id == ^ticket.id)
      |> Ash.read_one!(domain: Helpdesk, actor: admin)

    assert incident.severity == "sev1"
    assert incident.impact_scope == "全社"

    view
    |> form("#incident-event-form",
      incident_event: %{"phase" => "mitigation", "body" => "暫定対応を開始"}
    )
    |> render_submit()

    assert has_element?(view, "#incident-timeline", "暫定対応を開始")

    events =
      IncidentEvent
      |> filter(incident_id == ^incident.id)
      |> Ash.read!(domain: Helpdesk, actor: admin)

    assert Enum.any?(events, &(&1.phase == "mitigation"))

    view
    |> form("#incident-demote-form")
    |> render_submit()

    demoted =
      Incident
      |> filter(ticket_id == ^ticket.id)
      |> Ash.read_one!(domain: Helpdesk, actor: admin)

    assert demoted.demoted_at != nil
    assert has_element?(view, "#incident-promote-form")
  end

  test "non-admin cannot promote a ticket", %{conn: conn} do
    {ticket, _admin} = create_ticket_with_admin!()
    user = create_user!(ticket.company_id, "user")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    refute has_element?(view, "#incident-promote-form")
    assert render(view) =~ "インシデント操作の権限がありません"
  end

  defp create_ticket_with_admin! do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    requester = create_user!(company.id, "user")
    product = create_product!(company)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: "Incident UI ticket",
        product_id: product.id,
        requester_id: requester.id
      })
      |> Ash.create!(domain: Helpdesk)

    {ticket, admin}
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Incident UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "incident-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Incident UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Incident UI Product #{System.unique_integer([:positive])}",
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
