defmodule HelpdeskCommanderWeb.GlobalPublicationLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "an admin approves a pending global publication from the ticket view", %{conn: conn} do
    %{company: company, admin: admin, product: product} = context!()
    ticket = create_ticket!(product, admin, "p1")
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#global-publication-pending")
    assert has_element?(view, "#global-publication-pending", "全体公開候補")

    view
    |> element("#global-publication-pending button", "承認して全体公開")
    |> render_click()

    refute has_element?(view, "#global-publication-pending")

    updated = Ash.get!(Ticket, ticket.id, domain: Helpdesk, tenant: company.id)
    assert updated.visibility_scope == "global"
    assert updated.visibility_decided_by_id == admin.id
    assert render(view) =~ "全体公開"
  end

  test "an admin can reject a pending global publication", %{conn: conn} do
    %{admin: admin, product: product} = context!()
    ticket = create_ticket!(product, admin, "p1")
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> element("#global-publication-pending button", "却下")
    |> render_click()

    refute has_element?(view, "#global-publication-pending")

    updated = Ash.get!(Ticket, ticket.id, domain: Helpdesk, tenant: ticket.company_id)
    assert updated.visibility_scope == "company"
    assert updated.visibility_decided_by_id == admin.id
  end

  test "a non-privileged user does not see the approval controls", %{conn: conn} do
    %{admin: admin, product: product} = context!()
    ticket = create_ticket!(product, admin, "p1")
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    user = create_user!(ticket.company_id, "user")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#global-publication-pending")
    refute has_element?(view, "#global-publication-pending button", "承認して全体公開")
    assert render(view) =~ "承認・却下は管理者/リーダーのみ可能です"
  end

  defp context! do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    %{company: company, admin: admin, product: product}
  end

  defp create_ticket!(product, requester, priority) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Global UI #{priority}",
      priority: priority,
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Global UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "global-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Global UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Global UI Product #{System.unique_integer([:positive])}",
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
