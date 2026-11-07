defmodule HelpdeskCommanderWeb.AdminAttachmentRuleLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Attachments.HashRules

  @sha String.duplicate("c", 64)

  test "admin can add and delete a hash rule", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company, role: "admin")

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/attachment-rules")

    assert has_element?(view, "#hash-rule-form")
    assert has_element?(view, "#hash-rules")

    view
    |> form("#hash-rule-form", %{
      "rule" => %{"sha256" => @sha, "action" => "deny", "scope" => "company", "note" => "test"}
    })
    |> render_submit()

    assert has_element?(view, "#hash-rules", "拒否")
    assert {:ok, [rule]} = HashRules.list(company.id)
    assert rule.company_id == company.id
    assert rule.action == "deny"

    view
    |> element("#hash-rules button[phx-value-id=\"#{rule.id}\"]")
    |> render_click()

    assert {:ok, []} = HashRules.list(company.id)
  end

  test "rejects an invalid SHA256", %{conn: conn} do
    company = create_company!()
    admin = create_user!(company, role: "admin")

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/attachment-rules")

    view
    |> form("#hash-rule-form", %{
      "rule" => %{"sha256" => "not-a-hash", "action" => "deny", "scope" => "company", "note" => ""}
    })
    |> render_submit()

    assert has_element?(view, "[role=\"alert\"]")
    assert {:ok, []} = HashRules.list(company.id)
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Hash Rule UI Company #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company, role: role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "hash-rule-ui+#{System.unique_integer([:positive])}@example.com",
      display_name: "Hash Rule Admin",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
