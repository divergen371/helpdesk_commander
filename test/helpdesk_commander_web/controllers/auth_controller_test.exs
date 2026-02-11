defmodule HelpdeskCommanderWeb.AuthControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User

  @password "secret123!"

  test "renders sign in page", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")
    assert html_response(conn, 200) =~ "サインイン"
  end

  test "renders sign up page", %{conn: conn} do
    conn = get(conn, ~p"/sign-up")
    assert html_response(conn, 200) =~ "初回登録"
  end

  test "sign in rejects invalid company code", %{conn: conn} do
    conn =
      post(conn, ~p"/sign-in",
        session: %{
          "company_code" => "bad",
          "login" => "user",
          "password" => "pass"
        }
      )

    assert html_response(conn, 200) =~ "会社IDの形式が正しくありません"
  end

  test "sign in succeeds with valid credentials", %{conn: conn} do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, login_id: "agent")

    conn =
      post(conn, ~p"/sign-in",
        session: %{
          "company_code" => company_code,
          "login" => "agent",
          "password" => @password
        }
      )

    assert redirected_to(conn) == "/tickets"
  end

  test "sign in shows pending approval message", %{conn: conn} do
    company_code = unique_company_code()
    company = create_company!(company_code)
    _user = create_user!(company, status: "pending", login_id: "pending")

    conn =
      post(conn, ~p"/sign-in",
        session: %{
          "company_code" => company_code,
          "login" => "pending",
          "password" => @password
        }
      )

    assert html_response(conn, 200) =~ "承認待ちのためログインできません"
  end

  test "sign in blocks email login when login_id exists", %{conn: conn} do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, login_id: "agent")

    conn =
      post(conn, ~p"/sign-in",
        session: %{
          "company_code" => company_code,
          "login" => user.email,
          "password" => @password
        }
      )

    assert html_response(conn, 200) =~ "メールでのログインは初回のみです。login_idでログインしてください。"
  end

  test "sign up accepts pending user registration", %{conn: conn} do
    company_code = unique_company_code()
    company = create_company!(company_code)
    pending = create_user!(company, status: "pending", login_id: nil, with_password: false)

    conn =
      post(conn, ~p"/sign-up",
        registration: %{
          "company_code" => company_code,
          "email" => pending.email,
          "display_name" => "New Name",
          "password" => @password,
          "password_confirmation" => @password
        }
      )

    assert redirected_to(conn) == "/sign-in"
  end

  test "sign up rejects invalid company code", %{conn: conn} do
    conn =
      post(conn, ~p"/sign-up",
        registration: %{
          "company_code" => "bad",
          "email" => "test@example.com",
          "display_name" => "Test",
          "password" => @password,
          "password_confirmation" => @password
        }
      )

    assert html_response(conn, 200) =~ "会社IDの形式が正しくありません"
  end

  test "sign up redirects when already active", %{conn: conn} do
    company_code = unique_company_code()
    company = create_company!(company_code)
    user = create_user!(company, status: "active", login_id: "active")

    conn =
      post(conn, ~p"/sign-up",
        registration: %{
          "company_code" => company_code,
          "email" => user.email,
          "display_name" => "Test",
          "password" => @password,
          "password_confirmation" => @password
        }
      )

    assert redirected_to(conn) == "/sign-in"
  end

  test "sign out clears session", %{conn: conn} do
    conn = delete(conn, ~p"/sign-out")
    assert redirected_to(conn) == "/sign-in"
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
