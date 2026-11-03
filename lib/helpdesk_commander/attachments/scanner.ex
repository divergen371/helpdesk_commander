defmodule HelpdeskCommander.Attachments.Scanner do
  @moduledoc """
  添付ファイルのウイルススキャン。

  `:attachment_scan_command` に `{command, args}` またはコマンド文字列を設定すると、
  ファイルパスを末尾に追加して実行する。終了コード 0 を clean、1 を infected、
  それ以外を失敗として扱う（ClamAV の clamscan と同じ約束）。

  未設定の場合は `:skipped` を返す。開発・テストでは未検査のまま許可し、本番では
  `ATTACHMENT_SCAN_COMMAND=clamscan` のような設定を必須にする。
  """

  @type result ::
          {:ok, :clean | :infected | :skipped, String.t() | nil}
          | {:error, term()}

  @spec scan(Path.t()) :: result()
  def scan(path) do
    case Application.get_env(:helpdesk_commander, :attachment_scan_command) do
      nil ->
        {:ok, :skipped, "scanner not configured"}

      {command, args} when is_binary(command) and is_list(args) ->
        run(command, List.insert_at(args, -1, path))

      command when is_binary(command) ->
        run(command, [path])

      _other ->
        {:error, :invalid_scanner_config}
    end
  end

  defp run(command, args) do
    env = [{"CLOAK_KEY", ""}, {"PII_HMAC_SECRET", ""}, {"SECRET_KEY_BASE", ""}, {"DATABASE_URL", ""}]

    case System.cmd(command, args, stderr_to_stdout: true, env: env) do
      {output, 0} -> {:ok, :clean, trim(output)}
      {output, 1} -> {:ok, :infected, trim(output)}
      {output, status} -> {:error, {:exit_status, status, trim(output)}}
    end
  rescue
    error -> {:error, error}
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
