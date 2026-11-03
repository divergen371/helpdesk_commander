defmodule HelpdeskCommanderWeb.TicketSimilarityLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketLink

  test "shows related candidates without linking them automatically", %{conn: conn} do
    %{company: company, user: user, product: product} = context!()

    target =
      create_ticket!(product, user, %{
        subject: "ログインできない",
        description: "ログイン時に500エラーが発生する"
      })

    similar =
      create_ticket!(product, user, %{
        subject: "ログインできない",
        description: "ログインすると500エラーになる"
      })

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{target.public_id}")

    assert has_element?(view, "#ticket-suggestions")
    assert has_element?(view, "#ticket-suggestion-#{similar.id}")
    assert has_element?(view, "#ticket-suggestion-#{similar.id} button", "関連付ける")

    assert {:ok, []} = Ash.read(TicketLink, domain: Helpdesk, tenant: company.id)
  end

  test "links a suggested ticket only after the user clicks", %{conn: conn} do
    %{company: company, user: user, product: product} = context!()

    target = create_ticket!(product, user, %{subject: "VPN接続が切れる"})
    similar = create_ticket!(product, user, %{subject: "VPN接続が切れる", description: "1時間で切断"})

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{target.public_id}")

    view
    |> element("#ticket-suggestion-#{similar.id} button")
    |> render_click()

    assert {:ok, [link]} = Ash.read(TicketLink, domain: Helpdesk, tenant: company.id)
    assert link.ticket_id == target.id
    assert link.related_ticket_id == similar.id

    refute has_element?(view, "#ticket-suggestion-#{similar.id}")
    assert has_element?(view, "#ticket-links")
  end

  test "external users do not see suggestions", %{conn: conn} do
    %{user: user, product: product} = context!()
    external = create_user!(user.company_id, "customer")

    target =
      create_ticket!(product, external, %{
        subject: "ログインできない",
        description: "ログイン時に500エラー"
      })

    _similar = create_ticket!(product, user, %{subject: "ログインできない"})

    conn = log_in(conn, external)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{target.public_id}")

    refute has_element?(view, "#ticket-suggestions")
  end

  defp context! do
    company = create_company!()
    user = create_user!(company.id, "admin")
    product = create_product!(company)

    %{company: company, user: user, product: product}
  end

  defp create_ticket!(product, requester, attrs) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: Map.get(attrs, :subject, "Ticket"),
      description: Map.get(attrs, :description),
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Similarity UI Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "similarity-ui+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Similarity UI #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Similarity UI Product #{System.unique_integer([:positive])}",
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
