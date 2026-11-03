defmodule HelpdeskCommanderWeb.Plugs.ApiAuth do
  @moduledoc """
  API リクエストの認証。

  `Authorization: Bearer <token>` を優先し、なければ既存の Cookie セッションを使う。
  """

  @behaviour Plug

  import Plug.Conn

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommanderWeb.AuthToken

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, %User{status: "active"} = user} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_user_external?, Authorization.external?(user))

      {:ok, %User{}} ->
        unauthorized(conn, "アカウントが無効です")

      {:error, reason} ->
        ErrorLog.log_warn("api_auth", reason)
        unauthorized(conn, "認証が必要です")
    end
  end

  defp authenticate(conn) do
    case bearer_token(conn) do
      token when is_binary(token) ->
        with {:ok, claims} <- AuthToken.verify(token) do
          Accounts.get_user(claims.user_id)
        end

      nil ->
        case session_user(conn) do
          %User{} = user -> {:ok, user}
          nil -> {:error, :unauthenticated}
        end
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _other -> nil
    end
  end

  defp session_user(conn) do
    conn = fetch_session(conn)

    case get_session(conn, :user_id) do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, user} -> user
          _error -> nil
        end
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{error: %{code: "unauthorized", message: message}})
    |> halt()
  end
end
