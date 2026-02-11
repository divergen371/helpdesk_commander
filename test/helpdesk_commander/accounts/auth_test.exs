defmodule HelpdeskCommander.Accounts.AuthTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Auth
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User

  @password "secret123!"

  test "default_company creates internal company" do
    {:ok, company} = Auth.default_company()
    assert company.name == "Internal"
  end

  test "authenticate with login_id succeeds" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, login_id: "agent")

    assert {:ok, authed} = Auth.authenticate(company_code, "agent", @password)
    assert authed.id == user.id
  end

  test "authenticate with email generates login_id when missing" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, login_id: nil)

    assert {:ok, authed} = Auth.authenticate(company_code, user.email, @password)
    assert is_binary(authed.login_id)
    assert authed.login_id != ""
  end

  test "authenticate rejects email login when login_id is set" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, login_id: "agent")

    assert {:error, :email_login_disabled} = Auth.authenticate(company_code, user.email, @password)
  end

  test "authenticate pending user returns pending_approval" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, status: "pending", login_id: "pending")

    assert {:error, :pending_approval} = Auth.authenticate(company_code, "pending", @password)
  end

  test "authenticate with wrong password returns invalid_credentials" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, login_id: "agent")

    assert {:error, :invalid_credentials} = Auth.authenticate(company_code, "agent", "wrong")
  end

  test "authenticate with invalid company code returns error" do
    assert {:error, :invalid_company_code} = Auth.authenticate("bad", "user", "pass")
  end

  test "authenticate returns company_not_found for unknown company" do
    company_code = unique_company_code()
    assert {:error, :company_not_found} = Auth.authenticate(company_code, "user", "pass")
  end

  test "authenticate returns invalid_credentials when user is missing" do
    company_code = unique_company_code()
    _company = create_company!(company_code)

    assert {:error, :invalid_credentials} = Auth.authenticate(company_code, "missing", @password)
  end

  test "authenticate returns invalid_credentials when password is missing" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, login_id: "nopass", with_password: false)

    assert {:error, :invalid_credentials} = Auth.authenticate(company_code, "nopass", @password)
  end

  test "authenticate returns inactive for inactive user" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, status: "inactive", login_id: "inactive")

    assert {:error, :inactive} = Auth.authenticate(company_code, "inactive", @password)
  end

  test "register_pending_user updates password and display_name" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    pending = create_user!(company, status: "pending", login_id: nil, with_password: false)

    assert {:ok, user} =
             Auth.register_pending_user(
               company_code,
               pending.email,
               @password,
               @password,
               "New Name"
             )

    assert user.display_name == "New Name"
    assert is_binary(user.password_hash)
  end

  test "register_pending_user returns already_active for active users" do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, status: "active", login_id: "active")

    assert {:error, :already_active} =
             Auth.register_pending_user(company_code, user.email, @password, @password, "Name")
  end

  test "register_pending_user returns user_not_found when missing" do
    company_code = unique_company_code()
    _company = create_company!(company_code)

    assert {:error, :user_not_found} =
             Auth.register_pending_user(company_code, "missing@example.com", @password, @password, "Name")
  end

  defp create_company!(company_code) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: company_code
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(%Company{id: company_id}, opts) do
    email = Keyword.get(opts, :email, "user+#{System.unique_integer([:positive])}@example.com")
    status = Keyword.get(opts, :status, "active")
    role = Keyword.get(opts, :role, "user")
    login_id = Keyword.get(opts, :login_id, "user#{System.unique_integer([:positive])}")
    with_password? = Keyword.get(opts, :with_password, true)

    changeset =
      User
      |> Ash.Changeset.for_create(:create, %{
        email: email,
        display_name: "Test User",
        role: role,
        status: status,
        company_id: company_id,
        login_id: login_id
      })

    changeset =
      if with_password? do
        Ash.Changeset.force_change_attribute(changeset, :password_hash, Bcrypt.hash_pwd_salt(@password))
      else
        changeset
      end

    Ash.create!(changeset, domain: Accounts)
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
