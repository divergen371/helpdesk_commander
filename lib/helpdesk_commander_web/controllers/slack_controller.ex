defmodule HelpdeskCommanderWeb.SlackController do
  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Chat.Slack
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec events(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def events(conn, params) do
    raw_body = conn.assigns[:raw_body] || ""
    timestamp = header(conn, "x-slack-request-timestamp")
    signature = header(conn, "x-slack-signature")

    if Slack.verify_signature(raw_body, timestamp, signature) do
      handle_event(conn, params)
    else
      send_resp(conn, 401, "invalid signature")
    end
  end

  defp handle_event(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  defp handle_event(conn, %{"type" => "event_callback", "event" => event}) do
    if ignorable?(event) do
      send_resp(conn, 200, "ok")
    else
      case Slack.ingest(event) do
        {:ok, _result} ->
          send_resp(conn, 200, "ok")

        {:error, error} ->
          ErrorLog.log_error("slack_controller.ingest", error, event: redact_event(event))
          send_resp(conn, 500, "error")
      end
    end
  end

  defp handle_event(conn, _params), do: send_resp(conn, 200, "ok")

  defp ignorable?(event) do
    event["type"] != "message" or is_binary(event["bot_id"]) or is_binary(event["subtype"]) or
      not is_binary(event["thread_ts"])
  end

  defp redact_event(event) do
    Map.take(event, ["type", "subtype", "channel", "thread_ts", "ts", "user"])
  end

  defp header(conn, name) do
    conn
    |> get_req_header(name)
    |> List.first()
  end
end
