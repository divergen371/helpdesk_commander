defmodule HelpdeskCommanderWeb.SSOController do
  @moduledoc """
  SSO（OIDC）ログインの開始と Callback。
  パスワードログインと同じく Cookie セッション（`put_session(:user_id)`）で認証する。
  """

  use HelpdeskCommanderWeb, :controller

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.SSO
  alias HelpdeskCommander.SSO.Oidc
  alias HelpdeskCommander.Support.CompanyCode
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Support.PiiHash

  @spec new(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new(conn, %{"company_code" => company_code}) do
    if SSO.enabled?() do
      start_authorization(conn, company_code)
    else
      conn
      |> put_flash(:error, "SSO は無効です")
      |> redirect(to: ~p"/sign-in")
    end
  end

  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, params) do
    case get_session(conn, :sso) do
      %{company_code: company_code, session_params: session_params} ->
        finish_sign_in(conn, company_code, params, session_params)

      _other ->
        conn
        |> put_flash(:error, "SSO のセッションが見つかりません。最初からやり直してください。")
        |> redirect(to: ~p"/sign-in")
    end
  end

  defp start_authorization(conn, company_code) do
    with {:ok, _company} <- fetch_company(company_code),
         {:ok, %{url: url, session_params: session_params}} <- Oidc.authorize_url() do
      conn
      |> put_session(:sso, %{company_code: company_code, session_params: session_params})
      |> redirect(external: url)
    else
      {:error, :company_not_found} ->
        conn
        |> put_flash(:error, "会社が見つかりません")
        |> redirect(to: ~p"/sign-in")

      {:error, :sso_failed} ->
        conn
        |> put_flash(:error, "SSO の開始に失敗しました")
        |> redirect(to: ~p"/sign-in")
    end
  end

  defp finish_sign_in(conn, company_code, params, session_params) do
    oauth2_params =
      %{
        "code" => params["code"],
        "state" => params["state"]
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    case find_or_provision_user(company_code, oauth2_params, session_params) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> delete_session(:sso)
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/tickets")

      {:error, :sso_failed} ->
        flash_and_back(conn, "SSO 認証に失敗しました")

      {:error, :sso_not_allowed} ->
        flash_and_back(conn, "この IdP ユーザーは未登録です。先に会社側でアカウントを発行してください。")

      {:error, :invalid_sso_email} ->
        flash_and_back(conn, "IdP からメールアドレスを取得できませんでした")

      {:error, :company_not_found} ->
        flash_and_back(conn, "会社が見つかりません")

      {:error, :pending_approval} ->
        flash_and_back(conn, "承認待ちのためログインできません")

      {:error, :account_suspended} ->
        flash_and_back(conn, "アカウントは現在停止されています")

      {:error, :account_deleted} ->
        flash_and_back(conn, "このアカウントは削除済みです")
    end
  end

  defp find_or_provision_user(company_code, oauth2_params, session_params) do
    with {:ok, claims} <- Oidc.callback(oauth2_params, session_params),
         {:ok, company} <- fetch_company(company_code),
         {:ok, email} <- resolve_email(claims) do
      company.id
      |> fetch_or_create(email, claims)
      |> check_user_status()
    end
  end

  defp check_user_status({:ok, user}), do: ensure_sso_active(user)
  defp check_user_status(error), do: error

  defp resolve_email(claims) do
    case SSO.resolve_email(claims) do
      nil -> {:error, :invalid_sso_email}
      email -> {:ok, email}
    end
  end

  defp fetch_company(company_code) do
    case CompanyCode.hash(company_code) do
      {:ok, hashed} ->
        case Company
             |> filter(company_code_hash == ^hashed)
             |> Ash.read_one(domain: Accounts)
             |> log_read_error("sso.fetch_company") do
          {:ok, %Company{} = company} -> {:ok, company}
          _other -> {:error, :company_not_found}
        end

      {:error, _reason} ->
        {:error, :company_not_found}
    end
  end

  defp fetch_or_create(company_id, email, claims) do
    email_hash = PiiHash.email(email)
    query = filter(User, company_id == ^company_id and email_hash == ^email_hash)

    case Ash.read_one(query, domain: Accounts) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:ok, nil} ->
        provision_user(company_id, email, claims)

      {:error, error} ->
        ErrorLog.log_error("sso.fetch_user", error)
        {:error, :sso_failed}
    end
  end

  defp provision_user(company_id, email, claims) do
    with {:ok, params} <- SSO.build_user_params(claims, email) do
      changeset =
        Ash.Changeset.for_create(User, :create, %{
          company_id: company_id,
          email: email,
          display_name: params.display_name,
          role: params.role,
          status: params.status
        })

      case Ash.create(changeset, domain: Accounts) do
        {:ok, user} ->
          {:ok, user}

        {:error, error} ->
          ErrorLog.log_error("sso.provision_user", error)
          {:error, :sso_failed}
      end
    end
  end

  defp ensure_sso_active(%User{status: "active"} = user), do: {:ok, user}
  defp ensure_sso_active(%User{status: "pending"}), do: {:error, :pending_approval}
  defp ensure_sso_active(%User{status: "suspended"}), do: {:error, :account_suspended}
  defp ensure_sso_active(%User{status: "anonymized"}), do: {:error, :account_deleted}

  defp log_read_error(result, label) do
    case result do
      {:error, error} ->
        ErrorLog.log_error(label, error)
        result

      _ok ->
        result
    end
  end

  defp flash_and_back(conn, message) do
    conn
    |> configure_session(renew: true)
    |> delete_session(:sso)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end
end
