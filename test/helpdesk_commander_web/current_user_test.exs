defmodule HelpdeskCommanderWeb.CurrentUserTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
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
end
