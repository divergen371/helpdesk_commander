defmodule HelpdeskCommanderWeb.ReportControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "downloads a CSV summary for the requested period", %{conn: conn} do
    company = create_company!()
    user = create_user!(company.id, "admin")
    product = create_product!(company)
    _ticket = create_ticket!(product, user)

    conn = log_in(conn, user)
    from = Date.add(Date.utc_today(), -7)
    to = Date.utc_today()

    conn = get(conn, "/reports/analytics.csv?from=#{Date.to_iso8601(from)}&to=#{Date.to_iso8601(to)}")

    body = response(conn, 200)
    assert body =~ "\"section\",\"key\",\"count\",\"average_age_hours\""
    assert body =~ "\"summary\",\"total_count\",1,"
    assert body =~ "\"period\",\"from\",#{Date.to_iso8601(from)}"

    [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/csv"

    [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "analytics-"
  end

  test "falls back to the default period for invalid dates", %{conn: conn} do
    company = create_company!()
    user = create_user!(company.id, "admin")

    conn = log_in(conn, user)
    conn = get(conn, "/reports/analytics.csv?from=invalid&to=invalid")

    body = response(conn, 200)
    {default_from, _default_to} = HelpdeskCommander.Helpdesk.Analytics.default_period()
    assert body =~ "\"period\",\"from\",#{Date.to_iso8601(default_from)}"
  end

  test "redirects unauthenticated users", %{conn: conn} do
    conn = get(conn, "/reports/analytics.csv")

    assert redirected_to(conn) == "/sign-in"
  end

  test "rejects external users", %{conn: conn} do
    company = create_company!()
    external = create_user!(company.id, "customer")

    conn = log_in(conn, external)
    conn = get(conn, "/reports/analytics.csv")

    assert redirected_to(conn) == "/sign-in"
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Report Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "report+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Report #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Report Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Report ticket",
      product_id: product.id,
      requester_id: requester.id
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
