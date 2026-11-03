defmodule HelpdeskCommanderWeb.ReportController do
  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk.Analytics
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec analytics_csv(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def analytics_csv(conn, params) do
    case current_user(conn) do
      %User{} = user ->
        {from, to} = period(params)

        case Analytics.summarize(user.company_id, from: from, to: to) do
          {:ok, summary} ->
            conn
            |> put_resp_content_type("text/csv")
            |> put_resp_header(
              "content-disposition",
              "attachment; filename=\"analytics-#{Date.to_iso8601(from)}-#{Date.to_iso8601(to)}.csv\""
            )
            |> send_resp(200, Analytics.to_csv(summary))

          {:error, error} ->
            ErrorLog.log_error("report.analytics_csv", error, user_id: user.id)
            send_resp(conn, 500, "集計に失敗しました")
        end

      nil ->
        conn
        |> put_flash(:error, "ログインが必要です")
        |> redirect(to: ~p"/sign-in")
        |> halt()
    end
  end

  defp current_user(conn) do
    case get_session(conn, :user_id) do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          {:ok, %User{status: "active"} = user} ->
            if Authorization.internal?(user), do: user, else: nil

          _result ->
            nil
        end
    end
  end

  defp period(params) do
    with {:ok, from} <- Date.from_iso8601(params["from"] || ""),
         {:ok, to} <- Date.from_iso8601(params["to"] || ""),
         true <- Date.compare(from, to) != :gt do
      {from, to}
    else
      _error -> Analytics.default_period()
    end
  end
end
