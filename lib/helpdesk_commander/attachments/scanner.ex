defmodule HelpdeskCommander.Attachments.Scanner do
  @moduledoc """
  添付ファイルのウイルススキャン。

  `:attachment_scan_command` に `{command, args}` またはコマンド文字列を設定すると、
  ファイルパスを末尾に追加して実行する。終了コード 0 を clean、1 を infected、
  それ以外を失敗として扱う（ClamAV の clamscan と同じ約束）。

  fail-closed 方針:

  - 未設定で `:attachment_scan_allow_skipped`（既定 false）が false のときは
    `{:error, :scanner_not_configured}` を返す。開発・テストでは allow_skipped を
    true にして `:skipped` を許可する。本番では未設定のまま起動できない
    （`config/runtime.exs` で必須化）ので、実質的に skipped は発生しない。
  - スキャンは既定 30 秒でタイムアウトし、`{:error, :scan_timeout}` を返す。
    設定不備は `{:error, :invalid_scanner_config}`。いずれも呼び出し側で
    `failed` として隔離する。
  """

  alias HelpdeskCommander.Support.CommandRunner

  @default_timeout_ms 30_000

  @type result ::
          {:ok, :clean | :infected | :skipped, String.t() | nil}
          | {:error, term()}

  @spec scan(Path.t()) :: result()
  def scan(path) do
    case Application.get_env(:helpdesk_commander, :attachment_scan_command) do
      nil ->
        if allow_skipped?() do
          {:ok, :skipped, "scanner not configured"}
        else
          {:error, :scanner_not_configured}
        end

      {command, args} when is_binary(command) and is_list(args) ->
        run(command, List.insert_at(args, -1, path))

      command when is_binary(command) ->
        run(command, [path])

      _other ->
        {:error, :invalid_scanner_config}
    end
  end

  defp run(command, args) do
    case CommandRunner.run(command, args, timeout: scan_timeout_ms()) do
      {:ok, output, 0} -> {:ok, :clean, trim(output)}
      {:ok, output, 1} -> {:ok, :infected, trim(output)}
      {:ok, output, status} -> {:error, {:exit_status, status, trim(output)}}
      {:error, :timeout} -> {:error, :scan_timeout}
      {:error, reason} -> {:error, {:scan_error, reason}}
    end
  end

  defp allow_skipped? do
    Application.get_env(:helpdesk_commander, :attachment_scan_allow_skipped, false)
  end

  defp scan_timeout_ms do
    timeout = Application.get_env(:helpdesk_commander, :attachment_scan_timeout_ms, @default_timeout_ms)

    if is_integer(timeout) and timeout > 0 do
      timeout
    else
      @default_timeout_ms
    end
  end

  defp trim(output) do
    value =
      output
      |> to_string()
      |> String.trim()
      |> String.slice(0, 500)

    case value do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
