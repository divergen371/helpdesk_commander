defmodule HelpdeskCommanderWeb.RelationGraphLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketGraph
  alias HelpdeskCommander.Helpdesk.TicketRelations

  test "shows the company relation graph", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    root = create_ticket!(user, "Root")
    related = create_ticket!(user, "Related")

    {:ok, _} = TicketRelations.create_link(root, related.id, "related", user)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/relations")

    assert has_element?(view, "#ticket-graph")
    assert has_element?(view, "h1", "関係グラフ")
  end

  test "build_overview includes tickets and links", %{conn: _conn} do
    company = create_company!()
    user = create_user!(company)
    root = create_ticket!(user, "Root")
    related = create_ticket!(user, "Related")
    {:ok, _} = TicketRelations.create_link(root, related.id, "blocks", user)

    assert {:ok, %{nodes: nodes, edges: edges}} = TicketGraph.build_overview(company.id)
    assert length(nodes) == 2
    assert length(edges) == 1
    assert hd(edges)["relation"] == "blocks"
  end

  test "build_overview uses a compact grid and short edge labels" do
    company = create_company!()
    user = create_user!(company)
    first = create_ticket!(user, "First")
    second = create_ticket!(user, "Second")
    _third = create_ticket!(user, "Third")
    {:ok, _} = TicketRelations.create_link(first, second.id, "blocks", user)

    assert {:ok, %{nodes: nodes, edges: [edge]}} = TicketGraph.build_overview(company.id)
    assert edge["label"] == "依存"

    ys = nodes |> Enum.map(& &1["y"]) |> Enum.uniq()
    assert length(ys) == 2
  end

  test "build_overview centers a single ticket" do
    company = create_company!()
    user = create_user!(company)
    _ticket = create_ticket!(user, "Only")

    assert {:ok, %{nodes: [node]}} = TicketGraph.build_overview(company.id)
    assert node["x"] == 0.0
    assert node["y"] == 0.0
  end

  test "external user is redirected away from the graph", %{conn: conn} do
    company = create_company!()
    external = create_user!(company, role: "customer")

    conn = log_in(conn, external)
    assert {:error, {:redirect, %{to: "/tickets"}}} = live(conn, ~p"/relations")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company, opts \\ []) do
    role = Keyword.get(opts, :role, "user")

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "graph+#{System.unique_integer([:positive])}@example.com",
      display_name: "Graph User",
      role: role,
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
