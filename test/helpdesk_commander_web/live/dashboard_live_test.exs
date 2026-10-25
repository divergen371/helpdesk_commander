defmodule HelpdeskCommanderWeb.DashboardLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "unauthenticated user is redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
  end

  test "authenticated user sees the dashboard", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    _ticket = create_ticket!(user, "Dashboard ticket")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "h1", "今日の運用を、ひと目で。")
    assert has_element?(view, "p", "Dashboard ticket")
    assert has_element?(view, "p", "チケット")
    assert has_element?(view, "p", "タスク")
    assert has_element?(view, "p", "有効な製品")
    assert has_element?(view, "p", "未読通知")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "dashboard+#{System.unique_integer([:positive])}@example.com",
      display_name: "Dashboard User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(user, subject) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: subject,
      description: subject,
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
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
