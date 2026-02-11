defmodule HelpdeskCommanderWeb.AdminUserLive.PendingTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User

  test "admin can view and approve pending users", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company, role: "admin", status: "active")
    pending = create_user!(company, role: "user", status: "pending")

    conn = log_in(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/admin/pending-users")

    assert has_element?(view, "#pending-users")
    assert has_element?(view, "td", pending.email)

    view
    |> element("button[phx-click=\"approve\"][phx-value-id=\"#{pending.id}\"]")
    |> render_click()

    updated = Ash.get!(User, %{id: pending.id}, domain: Accounts)
    assert updated.status == "active"
  end

  test "approve handles missing user id", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company, role: "admin", status: "active")

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/pending-users")

    render_click(view, "approve", %{"id" => "0"})

    assert has_element?(view, "[role=\"alert\"]")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(%Company{id: company_id}, opts) do
    email = Keyword.get(opts, :email, "user+#{System.unique_integer([:positive])}@example.com")
    status = Keyword.get(opts, :status, "active")
    role = Keyword.get(opts, :role, "user")

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      role: role,
      status: status,
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp unique_company_code do
    suffix =
      System.unique_integer([:positive])
      |> rem(900_000)
      |> Kernel.+(100_000)
      |> Integer.to_string()

    "A-#{suffix}"
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
