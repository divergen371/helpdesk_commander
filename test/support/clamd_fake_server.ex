defmodule HelpdeskCommander.ClamdFakeServer do
  @moduledoc """
  テスト用の clamd 互換 TCP サーバー（HC-21）。

  `start/1` で 127.0.0.1 の空きポートで待ち受け、1 接続 1 コマンドで応答する。

  - `:mode` — `:clean` / `:infected` / `:eicar`（EICAR 文字列の有無で判定）/ `:error`
    / `:silent`（応答を返さない。タイムアウト検証用）
  - `:version` — VERSION 応答の文字列
  """

  @eicar "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

  @spec start(keyword()) :: {:ok, :inet.port_number(), pid()} | {:error, term()}
  def start(opts \\ []) do
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, listen} =
          :gen_tcp.listen(0, [
            :binary,
            packet: :raw,
            active: false,
            ip: {127, 0, 0, 1},
            reuseaddr: true
          ])

        {:ok, port} = :inet.port(listen)
        send(parent, {:listening, port})
        accept_loop(listen, opts)
      end)

    receive do
      {:listening, port} -> {:ok, port, pid}
    after
      5_000 -> {:error, :clamd_fake_start_timeout}
    end
  end

  defp accept_loop(listen, opts) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        serve(socket, opts)
        accept_loop(listen, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp serve(socket, opts) do
    read = read_command(socket, "")
    respond_or_wait(socket, read, opts)
  end

  # :silent は応答を返さず接続を開いたままにする（クライアント側のタイムアウト検証用）
  defp respond_or_wait(socket, {:ok, line, rest}, opts) do
    if Keyword.get(opts, :mode, :clean) == :silent and String.contains?(line, "INSTREAM") do
      {:ok, _body} = read_stream(socket, rest, "")
      :ok
    else
      respond(socket, String.trim_trailing(line, "\n"), rest, opts)
      :gen_tcp.close(socket)
    end
  end

  defp respond_or_wait(socket, {:error, _reason}, _opts) do
    :gen_tcp.close(socket)
  end

  defp respond(socket, line, rest, opts) do
    mode = Keyword.get(opts, :mode, :clean)
    version = Keyword.get(opts, :version, "ClamAV 1.4.2/27608/Thu Nov  6 09:00:00 2026")

    cond do
      String.ends_with?(line, "PING") ->
        reply(socket, "PONG")

      String.ends_with?(line, "VERSION") ->
        reply(socket, version)

      String.ends_with?(line, "RELOAD") ->
        reply(socket, Keyword.get(opts, :reload_response, "RELOAD: succeeded"))

      String.contains?(line, "INSTREAM") ->
        {:ok, body} = read_stream(socket, rest, "")
        reply(socket, stream_response(mode, body))

      true ->
        reply(socket, "UNKNOWN COMMAND")
    end
  end

  defp stream_response(:silent, _body), do: nil
  defp stream_response(:clean, _body), do: "stream: OK"
  defp stream_response(:infected, _body), do: "stream: Eicar-Signature FOUND"
  defp stream_response(:error, _body), do: "ERROR: database problem"

  defp stream_response(:eicar, body) do
    if String.contains?(body, @eicar) do
      "stream: Eicar-Signature FOUND"
    else
      "stream: OK"
    end
  end

  defp reply(_socket, nil), do: :ok

  defp reply(socket, response) do
    :gen_tcp.send(socket, response <> <<0>>)
  end

  defp read_command(socket, buffer) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        combined = buffer <> data

        case :binary.split(combined, "\n") do
          [line, rest] -> {:ok, line <> "\n", rest}
          [_partial] -> read_command(socket, combined)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_stream(socket, buffer, acc) do
    case buffer do
      <<0::32-big, _rest::binary>> ->
        {:ok, acc}

      <<size::32-big, data::binary-size(size), rest::binary>> ->
        read_stream(socket, rest, acc <> data)

      _partial ->
        case :gen_tcp.recv(socket, 0, 5_000) do
          {:ok, more} -> read_stream(socket, buffer <> more, acc)
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
