defmodule HelpdeskCommanderWeb.SSOControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Auth
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.SSOStubHTTPAdapter

  @default_code Auth.default_company_code()

  @sso_config [
    enabled: true,
    base_url: "http://idp.localhost",
    client_id: "test-client-id",
    client_secret: "test-client-secret",
    redirect_uri: "http://www.example.com/auth/sso/callback",
    id_token_signed_response_alg: "HS256",
    fixed_nonce: "test-nonce-123",
    role_claim: "groups",
    admin_group: "helpdesk-admins",
    http_adapter: SSOStubHTTPAdapter
  ]

  setup do
    original = Application.get_env(:helpdesk_commander, :sso)
    Application.put_env(:helpdesk_commander, :sso, @sso_config)
    on_exit(fn -> restore(original) end)

    :ok
  end

  describe "GET /auth/sso/start/:company_code" do
    test "redirects to the IdP and stores the SSO session", %{conn: conn} do
      _company = Auth.default_company!()

      conn = get(conn, "/auth/sso/start/#{@default_code}")

      assert redirected_to(conn) =~ "http://idp.localhost/authorize"
      assert redirected_to(conn) =~ "state="

      sso = get_session(conn, :sso)
      assert is_map(sso)

      assert sso[:company_code] == @default_code

      assert is_binary(sso.session_params.state)
    end

    test "rejects an unknown company", %{conn: conn} do
      conn = get(conn, "/auth/sso/start/A-999999")

      assert redirected_to(conn) == "/sign-in"
      assert flash_message(conn) =~ "会社が見つかりません"
    end
  end

  describe "GET /auth/sso/callback" do
    test "signs in an existing active user", %{conn: conn} do
      _company = Auth.default_company!()
      user = create_user!(@default_code, "taro@example.com", "admin")
      {conn, redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp("taro@example.com")
      conn = callback(conn, redirect_params)

      assert redirected_to(conn) == "/tickets"
      assert get_session(conn, :user_id) == user.id
    end

    test "provisions a pending user for an unknown IdP user", %{conn: conn} do
      _company = Auth.default_company!()
      {conn, redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp("new-user@example.com")
      conn = callback(conn, redirect_params)

      assert redirected_to(conn) == "/sign-in"
      assert flash_message(conn) =~ "承認待ち"

      email_hash = HelpdeskCommander.Support.PiiHash.email("new-user@example.com")

      created =
        User
        |> filter(company_id == ^company_id(@default_code) and email_hash == ^email_hash)
        |> Ash.read_one!(domain: Accounts)

      assert created.status == "pending"
      assert created.role == "user"
      assert created.display_name == "SSO Test User"
    end

    test "maps the admin group and provisions an active user", %{conn: conn} do
      patch_sso_config(auto_provision: "active")

      _company = Auth.default_company!()
      {conn, redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp("admin@example.com", ["helpdesk-admins"], "管理者 太郎")
      conn = callback(conn, redirect_params)

      assert redirected_to(conn) == "/tickets"

      email_hash = HelpdeskCommander.Support.PiiHash.email("admin@example.com")

      created =
        User
        |> filter(company_id == ^company_id(@default_code) and email_hash == ^email_hash)
        |> Ash.read_one!(domain: Accounts)

      assert created.role == "admin"
      assert created.status == "active"
      assert get_session(conn, :user_id) == created.id
    end

    test "rejects when auto provisioning is disabled", %{conn: conn} do
      patch_sso_config(auto_provision: false)

      _company = Auth.default_company!()
      {conn, redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp("blocked@example.com")
      conn = callback(conn, redirect_params)

      assert redirected_to(conn) == "/sign-in"
      assert flash_message(conn) =~ "未登録"
    end

    test "rejects an invalid state", %{conn: conn} do
      _company = Auth.default_company!()
      {conn, _redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp("taro@example.com")
      conn = get(conn, "/auth/sso/callback?code=stub-code&state=forged-state")

      assert redirected_to(conn) == "/sign-in"
      assert flash_message(conn) =~ "失敗"
    end

    test "rejects an IdP response without an email", %{conn: conn} do
      _company = Auth.default_company!()
      {conn, redirect_params, _location} = start_sso(conn)

      fetch_user_from_idp(nil)
      conn = callback(conn, redirect_params)

      assert redirected_to(conn) == "/sign-in"
      assert flash_message(conn) =~ "メールアドレスを取得できません"
    end
  end

  test "callback without the SSO session redirects back", %{conn: conn} do
    conn = get(conn, "/auth/sso/callback?code=x&state=y")

    assert redirected_to(conn) == "/sign-in"
    assert flash_message(conn) =~ "セッション"
  end

  defp start_sso(conn) do
    conn = get(conn, "/auth/sso/start/#{@default_code}")
    uri = URI.parse(redirected_to(conn))
    {conn, URI.decode_query(uri.query), URI.to_string(%{uri | query: nil})}
  end

  defp callback(conn, redirect_params) do
    state = redirect_params["state"]

    conn
    |> recycle()
    |> get("/auth/sso/callback?code=stub-code&state=#{state}")
  end

  defp fetch_user_from_idp(email, groups \\ [], name \\ "SSO Test User") do
    SSOStubHTTPAdapter.set_user(email, groups, name)
  end

  defp company_id(company_code) do
    Company
    |> filter(company_code_hash == ^HelpdeskCommander.Support.CompanyCode.hash!(company_code))
    |> Ash.read_one!(domain: Accounts)
    |> Map.get(:id)
  end

  defp patch_sso_config(overrides) do
    Application.put_env(:helpdesk_commander, :sso, Keyword.merge(@sso_config, overrides))
  end

  defp restore(nil), do: Application.delete_env(:helpdesk_commander, :sso)

  defp restore(config) when is_list(config) do
    Application.put_env(:helpdesk_commander, :sso, config)
  end

  defp flash_message(conn) do
    Phoenix.Flash.get(Map.get(conn.assigns, :flash, %{}), :error) || ""
  end

  defp create_user!(company_code, email, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id(company_code),
      email: email,
      display_name: "SSO Test User #{System.unique_integer([:positive])}",
      role: role,
      status: "active"
    })
    |> Ash.create!(domain: Accounts)
  end
end
