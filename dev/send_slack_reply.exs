# ローカル擬似 Slack からスレッド返信を送る。
#
#   SLACK_SIGNING_SECRET=local-secret \
#     mix run dev/send_slack_reply.exs 1712345678.000001 "返信内容"
#
# 既定の送信先は http://127.0.0.1:4000/integrations/slack/events。

[thread_ts | text_parts] = System.argv()

if is_nil(thread_ts) or text_parts == [] do
  IO.puts("usage: mix run dev/send_slack_reply.exs <thread_ts> <text>")
  System.halt(1)
end

secret = System.get_env("SLACK_SIGNING_SECRET") || "local-secret"
app_url = System.get_env("LOCAL_APP_URL") || "http://127.0.0.1:4000"
channel = System.get_env("SLACK_CHAT_CHANNEL_ID") || "C-LOCAL"
text = Enum.join(text_parts, " ")

event = %{
  "type" => "event_callback",
  "event" => %{
    "type" => "message",
    "channel" => channel,
    "thread_ts" => thread_ts,
    "ts" => "#{System.system_time(:second)}.#{System.unique_integer([:positive])}",
    "text" => text,
    "user" => "U-LOCAL"
  }
}

raw = Jason.encode!(event)
timestamp = Integer.to_string(System.system_time(:second))
signature =
  "v0=" <>
    Base.encode16(
      :crypto.mac(:hmac, :sha256, secret, "v0:#{timestamp}:#{raw}"),
      case: :lower
    )

case Req.post("#{app_url}/integrations/slack/events",
       body: raw,
       headers: [
         {"content-type", "application/json"},
         {"x-slack-request-timestamp", timestamp},
         {"x-slack-signature", signature}
       ]
     ) do
  {:ok, %Req.Response{status: 200, body: body}} ->
    IO.puts("sent: #{inspect(body)}")

  {:ok, %Req.Response{status: status, body: body}} ->
    IO.puts("failed: HTTP #{status} #{inspect(body)}")
    System.halt(1)

  {:error, error} ->
    IO.puts("failed: #{inspect(error)}")
    System.halt(1)
end
