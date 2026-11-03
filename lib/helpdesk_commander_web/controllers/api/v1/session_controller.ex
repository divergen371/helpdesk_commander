defmodule HelpdeskCommanderWeb.Api.V1.SessionController do
  @moduledoc """
  API v1 の認証と自分の情報。
  """

  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Accounts.Auth
  alias HelpdeskCommanderWeb.AuthToken

  action_fallback HelpdeskCommanderWeb.Api.FallbackController

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"session" => params}) do
    create(conn, params)
  end

  def create(conn, %{"company_code" => company_code, "login" => login, "password" => password}) do
    case Auth.authenticate(company_code, login, password) do
      {:ok, user} ->
        token = AuthToken.sign(user)

        json(conn, %{
          token: token,
          token_type: "Bearer",
          expires_in: AuthToken.max_age(),
          user: user_json(user)
        })

      {:error, :pending_approval} ->
        conn
        |> put_status(403)
        |> json(%{error: %{code: "pending_approval", message: "承認待ちのためログインできません"}})

      {:error, reason} when reason in [:invalid_credentials, :email_login_disabled] ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_credentials", message: "認証情報が正しくありません"}})

      {:error, :account_suspended} ->
        conn
        |> put_status(403)
        |> json(%{error: %{code: "account_suspended", message: "アカウントは停止されています"}})

      {:error, _reason} ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_credentials", message: "認証情報が正しくありません"}})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "company_code, login, password が必要です",
        fields: %{}
      }
    })
  end

  @spec me(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def me(conn, _params) do
    json(conn, %{user: user_json(conn.assigns.current_user)})
  end

  defp user_json(user) do
    %{
      id: user.id,
      display_name: user.display_name,
      role: user.role,
      status: user.status,
      company_id: user.company_id
    }
  end
end
