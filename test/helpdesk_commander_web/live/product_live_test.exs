defmodule HelpdeskCommanderWeb.ProductLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query
  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommanderWeb.FormOptions

  test "user can create a product", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/products")

    view
    |> form("#product-form",
      form: %{"name" => "Chat", "description" => "Chat service"}
    )
    |> render_submit()

    product =
      Product
      |> filter(company_id == ^company.id)
      |> Ash.read_one!(domain: Helpdesk)

    assert product.name == "Chat"
    assert product.description == "Chat service"
    assert product.active
    assert has_element?(view, "#products", "Chat")
  end

  test "products are scoped to the current company", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    own = create_product!(company, "Own product")

    other_company = create_company!()
    other = create_product!(other_company, "Other product")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/products")

    assert has_element?(view, "#products", own.name)
    refute has_element?(view, "#products", other.name)

    assert {:error, {:live_redirect, %{to: "/products"}}} =
             live(log_in(build_conn(), user), ~p"/products/#{other.id}")
  end

  test "user can edit and deactivate a product", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    product = create_product!(company, "Original")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/products/#{product.id}")

    view
    |> form("#product-edit-form",
      form: %{"name" => "Updated", "description" => "Updated description"}
    )
    |> render_submit()

    updated = Ash.get!(Product, %{id: product.id}, domain: Helpdesk)
    assert updated.name == "Updated"
    assert updated.description == "Updated description"

    view
    |> element("button[phx-click=\"toggle_active\"]")
    |> render_click()

    deactivated = Ash.get!(Product, %{id: product.id}, domain: Helpdesk)
    refute deactivated.active

    assert {:ok, products} = FormOptions.load_products(user)
    refute Enum.any?(products, &(&1.id == product.id))
  end

  test "external user is redirected away from product management", %{conn: conn} do
    company = create_company!()
    external = create_user!(company, role: "customer")

    conn = log_in(conn, external)
    assert {:error, {:redirect, %{to: "/tickets"}}} = live(conn, ~p"/products")
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
      email: "product+#{System.unique_integer([:positive])}@example.com",
      display_name: "Product User",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company, name) do
    Product
    |> Ash.Changeset.for_create(:create, %{name: name, company_id: company.id})
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
