defmodule HelpdeskCommanderWeb.InquiryLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query
  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "external user submits an inquiry and is redirected to the generated ticket", %{conn: conn} do
    company = create_company!()
    user = create_user!(company, role: "customer")
    product = create_product!(company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/inquiries/new")

    view
    |> form("#inquiry-form",
      form: %{
        "subject" => "  ログインできません  ",
        "body" => "  500エラーが表示されます  ",
        "product_id" => to_string(product.id)
      }
    )
    |> render_submit()

    inquiry = latest_inquiry!()
    ticket = Ash.get!(Ticket, %{id: inquiry.ticket_id}, domain: Helpdesk)

    assert inquiry.subject == "ログインできません"
    assert inquiry.body == "500エラーが表示されます"
    assert inquiry.source == "web"
    assert inquiry.company_id == company.id
    assert inquiry.product_id == product.id
    assert inquiry.requester_id == user.id

    assert ticket.subject == inquiry.subject
    assert ticket.description == inquiry.body
    assert ticket.requester_id == user.id
    assert ticket.product_id == product.id

    assert_redirect(view, ~p"/tickets/#{ticket.public_id}")
  end

  test "internal user can submit an inquiry on behalf of a company user", %{conn: conn} do
    company = create_company!()
    agent = create_user!(company, role: "user")
    requester = create_user!(company, role: "customer")
    product = create_product!(company)

    conn = log_in(conn, agent)
    {:ok, view, _html} = live(conn, ~p"/inquiries/new")

    view
    |> form("#inquiry-form",
      form: %{
        "subject" => "代理受付",
        "body" => "顧客からの依頼",
        "product_id" => to_string(product.id),
        "requester_id" => to_string(requester.id)
      }
    )
    |> render_submit()

    inquiry = latest_inquiry!()
    ticket = Ash.get!(Ticket, %{id: inquiry.ticket_id}, domain: Helpdesk)

    assert inquiry.requester_id == requester.id
    assert ticket.requester_id == requester.id
    assert_redirect(view, ~p"/tickets/#{ticket.public_id}")
  end

  test "only products from the current company are offered", %{conn: conn} do
    company = create_company!()
    user = create_user!(company, role: "customer")
    product = create_product!(company)

    other_company = create_company!()
    other_product = create_product!(other_company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/inquiries/new")

    assert has_element?(view, "option[value=\"#{product.id}\"]")
    refute has_element?(view, "option[value=\"#{other_product.id}\"]")
  end

  test "blank subject or body is rejected", %{conn: conn} do
    company = create_company!()
    user = create_user!(company, role: "customer")
    product = create_product!(company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/inquiries/new")

    view
    |> form("#inquiry-form",
      form: %{
        "subject" => "   ",
        "body" => "   ",
        "product_id" => to_string(product.id)
      }
    )
    |> render_submit()

    assert has_element?(view, "#inquiry-form")
    assert Ash.read!(Inquiry, domain: Helpdesk) == []
  end

  test "internal user cannot submit on behalf of another company", %{conn: conn} do
    company = create_company!()
    agent = create_user!(company, role: "user")
    product = create_product!(company)

    other_company = create_company!()
    other_user = create_user!(other_company, role: "customer")

    conn = log_in(conn, agent)
    {:ok, view, _html} = live(conn, ~p"/inquiries/new")

    html =
      render_submit(view, "save", %{
        "form" => %{
          "subject" => "越境依頼",
          "body" => "別会社の依頼者",
          "product_id" => to_string(product.id),
          "requester_id" => to_string(other_user.id)
        }
      })

    assert html =~ "依頼者が見つかりません"
    assert Ash.read!(Inquiry, domain: Helpdesk) == []
  end

  test "unauthenticated user is redirected to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/inquiries/new")
  end

  defp latest_inquiry! do
    Inquiry
    |> sort(inserted_at: :desc)
    |> Ash.read_one!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company, opts) do
    role = Keyword.get(opts, :role, "user")

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "user+#{System.unique_integer([:positive])}@example.com",
      display_name: "Test User",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company.id
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
