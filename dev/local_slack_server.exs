# ローカル擬似 Slack サーバー。
#
#   mix run --no-halt dev/local_slack_server.exs
#
# 4010 番で chat.postMessage とメッセージ一覧を提供する。
# アプリ側は SLACK_API_BASE=http://127.0.0.1:4010/api を設定する。

defmodule LocalSlack.Store do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{counter: 0, messages: []} end, name: __MODULE__)
  end

  def add(message) do
    Agent.get_and_update(__MODULE__, fn state ->
      counter = state.counter + 1
      ts = "#{System.system_time(:second)}.#{String.pad_leading(to_string(counter), 6, "0")}"
      stored = Map.put(message, "ts", ts)

      {stored, %{state | counter: counter, messages: [stored | state.messages]}}
    end)
  end

  def messages, do: Agent.get(__MODULE__, & &1.messages)
end

defmodule LocalSlack.Router do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/api/chat.postMessage" do
    message =
      conn.body_params
      |> Map.take(["channel", "text", "thread_ts"])
      |> Map.put("received_at", DateTime.utc_now() |> DateTime.to_iso8601())

    stored = LocalSlack.Store.add(message)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        ok: true,
        channel: stored["channel"],
        ts: stored["ts"]
      })
    )
  end

  get "/api/messages" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(LocalSlack.Store.messages()))
  end

  get "/" do
    rows =
      LocalSlack.Store.messages()
      |> Enum.map(fn message ->
        """
        <tr>
          <td><code>#{message["ts"]}</code></td>
          <td>#{message["channel"]}</td>
          <td>#{message["thread_ts"] || "-"}</td>
          <td>#{message["text"]}</td>
        </tr>
        """
      end)
      |> Enum.join()

    html = """
    <!doctype html>
    <html lang="ja">
      <head>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="2">
        <title>Local Slack</title>
        <style>
          body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 2rem; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border-bottom: 1px solid #ddd; padding: .5rem; text-align: left; }
          code { background: #f3f4f6; padding: .1rem .3rem; }
        </style>
      </head>
      <body>
        <h1>Local Slack</h1>
        <p>アプリから届いたメッセージです。2秒ごとに更新します。</p>
        <table>
          <thead><tr><th>ts</th><th>channel</th><th>thread_ts</th><th>text</th></tr></thead>
          <tbody>#{rows}</tbody>
        </table>
      </body>
    </html>
    """

    send_resp(conn, 200, html)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

{:ok, _} = Application.ensure_all_started(:bandit)
{:ok, _} = LocalSlack.Store.start_link([])
port = System.get_env("LOCAL_SLACK_PORT", "4010") |> String.to_integer()
{:ok, _} = Bandit.start_link(plug: LocalSlack.Router, ip: {127, 0, 0, 1}, port: port)

IO.puts("Local Slack listening on http://127.0.0.1:#{port}")
IO.puts("Inspect messages at http://127.0.0.1:#{port}/")
Process.sleep(:infinity)
