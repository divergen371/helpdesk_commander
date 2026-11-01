defmodule HelpdeskCommanderWeb.SlaLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Sla
  alias HelpdeskCommander.Helpdesk.Ticket

  test "an admin edits the SLA targets for each priority", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/settings/sla")

    assert has_element?(view, "#sla-form-p1")
    assert has_element?(view, "#sla-form-p4")

    view
    |> form("#sla-form-p1",
      policy: %{
        "first_response_minutes" => "10",
        "mitigation_minutes" => "30",
        "resolution_minutes" => "120",
        "restoration_minutes" => "240"
      }
    )
    |> render_submit()

    assert {:ok, targets} = Sla.get_targets(company.id, "p1")
    assert targets == %{first_response: 10, mitigation: 30, resolution: 120, restoration: 240}
    assert render(view) =~ "個別設定"
  end

  test "a non-privileged user is redirected from the SLA settings", %{conn: conn} do
    company = create_company!()
    user = create_user!(company.id, "user")
    conn = log_in(conn, user)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/settings/sla")
  end

  test "the dashboard shows SLA breaches", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin)

    old = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)

    ticket
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:inserted_at, old)
    |> Ash.update!(domain: Helpdesk, tenant: company.id)

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#sla-breaches")
    assert has_element?(view, "#sla-breach-#{ticket.id}")
    assert render(view) =~ "一次応答"
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "SLA UI ticket",
      impact: "widespread",
      urgency: "critical",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "SLA UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "sla-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "SLA UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "SLA UI Product #{System.unique_integer([:positive])}",
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
