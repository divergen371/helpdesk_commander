defmodule HelpdeskCommanderWeb.CurrentUserTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommanderWeb.CurrentUser

  test "fetch returns nil when session has no user_id" do
    assert CurrentUser.fetch(%{}) == nil
  end

  test "fetch returns nil for invalid id" do
    assert CurrentUser.fetch(%{"user_id" => "abc"}) == nil
  end

  test "fetch returns user for string id" do
    company = create_company!()
    user = create_user!(company, role: "admin", status: "active")

    assert %User{id: id} = CurrentUser.fetch(%{"user_id" => "#{user.id}"})
    assert id == user.id
  end

  test "fetch returns user for atom id" do
    company = create_company!()
    user = create_user!(company, role: "user", status: "active")

    assert %User{id: id} = CurrentUser.fetch(%{user_id: user.id})
    assert id == user.id
  end

  test "role helpers evaluate correctly" do
    company = create_company!()
    admin = create_user!(company, role: "admin", status: "active")
    external = create_user!(company, role: "customer", status: "pending")

    assert CurrentUser.admin?(admin)
    refute CurrentUser.admin?(external)

    assert CurrentUser.external?(external)
    refute CurrentUser.external?(admin)

    assert CurrentUser.active?(admin)
    refute CurrentUser.active?(external)
  end

  test "id returns the user id or nil" do
    company = create_company!()
    user = create_user!(company)

    assert CurrentUser.id(user) == user.id
    assert CurrentUser.id(nil) == nil
  end

  test "nil-safe helpers return false" do
    refute CurrentUser.external?(nil)
    refute CurrentUser.admin?(nil)
    refute CurrentUser.active?(nil)
    refute CurrentUser.suspended?(nil)
    refute CurrentUser.anonymized?(nil)
  end

  test "suspended? and anonymized? reflect the account status" do
    company = create_company!()
    suspended = create_user!(company, status: "suspended")
    anonymized = create_user!(company, status: "anonymized")

    assert CurrentUser.suspended?(suspended)
    refute CurrentUser.suspended?(anonymized)
    assert CurrentUser.anonymized?(anonymized)
    refute CurrentUser.anonymized?(suspended)
  end

  test "display_label handles anonymized, system, suspended, and active users" do
    company = create_company!()

    assert CurrentUser.display_label(create_user!(company, status: "anonymized")) ==
             "削除済みユーザー"

    assert CurrentUser.display_label(create_user!(company, role: "system")) == "System"

    assert CurrentUser.display_label(create_user!(company, status: "suspended")) ==
             "Test User（無効）"

    active = create_user!(company)
    assert CurrentUser.display_label(active) == "Test User <#{active.email}>"
  end

  test "fetch returns nil for a missing user id" do
    assert CurrentUser.fetch(%{"user_id" => "999999999"}) == nil
  end

  test "fetch returns nil for unsupported id types" do
    assert CurrentUser.fetch(%{"user_id" => %{}}) == nil
    assert CurrentUser.fetch(%{"user_id" => 1.5}) == nil
  end

  test "Authorization.privileged_role? handles role strings and nil" do
    assert Authorization.privileged_role?("admin")
    assert Authorization.privileged_role?("leader")
    refute Authorization.privileged_role?("user")
    refute Authorization.privileged_role?(nil)
  end

  test "Authorization scopes roles and companies" do
    company = create_company!()
    other_company = create_company!()
    admin = create_user!(company, role: "admin")
    user = create_user!(company)

    assert Authorization.external?("customer")
    refute Authorization.external?("user")
    refute Authorization.external?(nil)

    assert Authorization.internal?("user")
    refute Authorization.internal?("customer")
    refute Authorization.internal?(nil)

    assert Authorization.same_company?(user, company.id)
    refute Authorization.same_company?(user, other_company.id)
    refute Authorization.same_company?(nil, company.id)

    assert Authorization.privileged_for_company?(admin, company.id)
    refute Authorization.privileged_for_company?(admin, other_company.id)
    refute Authorization.privileged_for_company?(nil, company.id)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(%Company{id: company_id}, opts \\ []) do
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
end
