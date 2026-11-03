defmodule HelpdeskCommanderWeb.MonitoringController do
  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Monitoring.Alerts
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    request_token = token(conn)

    cond do
      not Alerts.enabled?() ->
        send_resp(conn, 503, "monitoring integration is disabled")

      not Alerts.token_valid?(request_token) ->
        send_resp(conn, 401, "invalid token")

      true ->
        ingest(conn, params)
    end
  end

  defp ingest(conn, params) do
    case Alerts.ingest(params) do
      {:ok, results} ->
        payload = %{results: Enum.map(results, &serialize/1)}

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(202, Jason.encode!(payload))

      {:error, :invalid_payload} ->
        send_resp(conn, 422, "invalid payload")

      {:error, :company_not_found} ->
        send_resp(conn, 503, "monitoring company is not configured")

      {:error, :product_not_configured} ->
        send_resp(conn, 503, "monitoring product is not configured")

      {:error, error} ->
        ErrorLog.log_error("monitoring_controller.ingest", error)
        send_resp(conn, 500, "failed to ingest alert")
    end
  end

  defp serialize(result) do
    %{
      fingerprint: result.alert && result.alert.fingerprint,
      ticket_public_id: result.ticket && result.ticket.public_id,
      duplicate: result.duplicate?,
      ignored: result.ignored?
    }
  end

  defp token(conn) do
    case get_req_header(conn, "x-monitoring-token") do
      [token | _rest] ->
        token

      [] ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> token] -> token
          _other -> nil
        end
    end
  end
end
