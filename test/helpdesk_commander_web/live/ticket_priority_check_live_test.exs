defmodule HelpdeskCommanderWeb.TicketPriorityCheckLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "admin can view priority mismatch suggestion and accept it on ticket show", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    ticket =
      create_ticket!(product, admin, %{
        subject: "本番停止が発生しました",
        description: "全社的にログインできない状態です",
        priority: "p4"
      })

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#priority-check-card")
    assert has_element?(view, "#priority-check-status", "要確認")
    assert has_element?(view, "#priority-check-suggestion", "p1")
    assert has_element?(view, "#accept-priority-check")

    view
    |> element("#accept-priority-check")
    |> render_click()

    assert has_element?(view, "#priority-check-status", "OK")
    refute has_element?(view, "#accept-priority-check")
  end

  test "internal user can dismiss priority mismatch suggestion and it stays dismissed", %{
    conn: conn
  } do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    ticket =
      create_ticket!(product, admin, %{
        subject: "緊急の確認依頼",
        description: "確認のみです",
        priority: "p4"
      })

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    assert has_element?(view, "#priority-check-status", "要確認")
    assert has_element?(view, "#dismiss-priority-check")

    view
    |> element("#dismiss-priority-check")
    |> render_click()

    assert has_element?(view, "#priority-check-status", "却下済み")

    {:ok, reloaded_view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")
    assert has_element?(reloaded_view, "#priority-check-status", "却下済み")
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Priority UI Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_user!(company_id, role) do
    unique = System.unique_integer([:positive])

    User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      email: "pc-ui-#{unique}@example.com",
      display_name: "PC UI Admin",
      role: role,
      status: "active"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_product!(company) do
    unique = System.unique_integer([:positive])

    Product
    |> Ash.Changeset.for_create(:create, %{
      company_id: company.id,
      name: "Product #{unique}"
    })
    |> Ash.create!(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_ticket!(product, requester, attrs) do
    defaults = %{
      company_id: product.company_id,
      product_id: product.id,
      requester_id: requester.id,
      subject: "Default subject",
      description: "Default description",
      type: "question",
      impact: "minor",
      urgency: "low",
      priority: "p4"
    }

    Ticket
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, attrs))
    |> Ash.create!(domain: Helpdesk, tenant: product.company_id, actor: requester)
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
