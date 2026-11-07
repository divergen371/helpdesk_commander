defmodule HelpdeskCommander.Attachments.Clamd do
  @moduledoc """
  clamd（TCP）プロトコルのクライアント（HC-21）。

  スキャナ自体を攻撃面にしないため、検査はサンドボックス化された clamd サイドカーへ
  委ねる。アプリ側は `INSTREAM` でファイル内容をストリーム送信するだけで、
  Docker ソケットも共有ボリュームも必要としない。

  設定は `config :helpdesk_commander, :attachment_scan_clamd` に

      host: "clamd", port: 3310

  を渡す（`config/runtime.exs` では `ATTACHMENT_SCAN_CLAMD_HOST` /
  `ATTACHMENT_SCAN_CLAMD_PORT`）。未設定なら `default_config/0` が `nil` を返し、
  呼び出し側はコマンド実行（`clamscan` 等）へフォールバックする。

  fail-closed: 接続失敗・タイムアウト・`ERROR` 応答はすべて `{:error, ...}` に
  正規化し、呼び出し側で `failed` として隔離する。
  """

  @default_port 3310
  @default_timeout_ms 30_000
  @chunk_size 64 * 1024
  @stream_terminator <<0, 0, 0, 0>>

  @type config :: %{host: String.t(), port: :inet.port_number(), timeout_ms: pos_integer()}

  @doc "clamd の接続設定。未設定または不正なら nil。"
  @spec default_config() :: config() | nil
  def default_config do
    case Application.get_env(:helpdesk_commander, :attachment_scan_clamd) do
      settings when is_list(settings) ->
        host = Keyword.get(settings, :host)
        port = Keyword.get(settings, :port, @default_port)

        if is_binary(host) and is_integer(port) and port > 0 do
          timeout = Keyword.get(settings, :timeout_ms, @default_timeout_ms)
          %{host: host, port: port, timeout_ms: positive_integer(timeout, @default_timeout_ms)}
        end

      _other ->
        nil
    end
  end

  @doc "PING。clamd の生存確認。"
  @spec ping(config() | nil) :: {:ok, String.t()} | {:error, term()}
  def ping(config \\ default_config())
  def ping(nil), do: {:error, :clamd_not_configured}
  def ping(config), do: command(config, "PING")

  @doc "VERSION。`ClamAV <version>/<sig>/<date>` 形式の応答を返す。"
  @spec version(config() | nil) :: {:ok, String.t()} | {:error, term()}
  def version(config \\ default_config())
  def version(nil), do: {:error, :clamd_not_configured}
  def version(config), do: command(config, "VERSION")

  @doc "RELOAD。シグネチャデータベースの再読込を指示する。"
  @spec reload(config() | nil) :: {:ok, String.t()} | {:error, term()}
  def reload(config \\ default_config())
  def reload(nil), do: {:error, :clamd_not_configured}
  def reload(config), do: command(config, "RELOAD")

  @doc """
  INSTREAM でファイルを検査する。

  - `{:ok, :clean, note}` — `stream: OK`
  - `{:ok, :infected, note}` — `stream: <name> FOUND`
  - `{:error, reason}` — 接続・タイムアウト・`ERROR` 応答など（fail-closed）
  """
  @spec scan_file(Path.t(), config() | nil) ::
          {:ok, :clean | :infected, String.t()} | {:error, term()}
  def scan_file(path, config \\ default_config())

  def scan_file(_path, nil), do: {:error, :clamd_not_configured}

  def scan_file(path, config) do
    case File.open(path, [:read, :binary], &instream(&1, config)) do
      {:ok, result} -> result
      {:error, reason} -> {:error, {:clamd_file_error, reason}}
    end
  end

  defp instream(io, config) do
    with {:ok, socket} <- connect(config),
         :ok <- :gen_tcp.send(socket, "nINSTREAM\n"),
         :ok <- send_chunks(socket, io),
         :ok <- :gen_tcp.send(socket, @stream_terminator) do
      response = recv_response(socket, config.timeout_ms)
      close(socket)
      parse_stream_response(response)
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_chunks(socket, io) do
    case IO.binread(io, @chunk_size) do
      :eof ->
        :ok

      {:error, reason} ->
        {:error, {:clamd_file_error, reason}}

      data when is_binary(data) ->
        with :ok <- :gen_tcp.send(socket, [<<byte_size(data)::32-big>>, data]) do
          send_chunks(socket, io)
        end
    end
  end

  defp command(config, name) do
    with {:ok, socket} <- connect(config),
         :ok <- :gen_tcp.send(socket, "n" <> name <> "\n") do
      response = recv_response(socket, config.timeout_ms)
      close(socket)
      response
    end
  end

  defp connect(%{host: host, port: port, timeout_ms: timeout}) do
    address = String.to_charlist(host)

    case :gen_tcp.connect(address, port, [:binary, active: false, packet: :raw], timeout) do
      {:ok, socket} -> {:ok, socket}
      {:error, reason} -> {:error, {:clamd_connect, reason}}
    end
  end

  defp recv_response(socket, timeout_ms, buffer \\ "")

  defp recv_response(socket, timeout_ms, buffer) do
    case :gen_tcp.recv(socket, 0, timeout_ms) do
      {:ok, data} ->
        combined = buffer <> data

        case split_at_terminator(combined) do
          {:ok, response} -> {:ok, response}
          :incomplete -> recv_response(socket, timeout_ms, combined)
        end

      {:error, :timeout} ->
        {:error, :clamd_timeout}

      {:error, reason} ->
        {:error, {:clamd_recv, reason}}
    end
  end

  # clamd はコマンドによって \0 終端と \n 終端の両方を使う。先に現れた方を終端とみなす。
  defp split_at_terminator(data) do
    null_at = binary_position(data, <<0>>)
    newline_at = binary_position(data, "\n")

    case {null_at, newline_at} do
      {:none, :none} ->
        :incomplete

      {:none, pos} ->
        {:ok, binary_part(data, 0, pos)}

      {pos, :none} ->
        {:ok, binary_part(data, 0, pos)}

      {pos, other} ->
        {:ok, binary_part(data, 0, min(pos, other))}
    end
  end

  defp binary_position(data, pattern) do
    case :binary.match(data, pattern) do
      :nomatch -> :none
      {pos, _len} -> pos
    end
  end

  defp close(socket), do: :gen_tcp.close(socket)

  defp parse_stream_response({:ok, "stream: OK"}), do: {:ok, :clean, "stream: OK"}
  defp parse_stream_response({:ok, "stream: " <> detection}), do: {:ok, :infected, detection}

  defp parse_stream_response({:ok, "ERROR" <> reason}) do
    message = reason |> String.trim_leading(":") |> String.trim()
    {:error, {:clamd_error, message}}
  end

  defp parse_stream_response({:ok, other}), do: {:error, {:clamd_unexpected_response, other}}
  defp parse_stream_response({:error, reason}), do: {:error, reason}

  defp positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, fallback), do: fallback
end
