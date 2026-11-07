defmodule HelpdeskCommander.Attachments.ScanMetadata do
  @moduledoc """
  スキャン結果のメタデータ（エンジン名・版・シグネチャ日時）を収集する（HC-17）。

  取得元は次の順:

  1. `:attachment_scan_version_command` が設定されていればそれを実行する
  2. スキャナコマンドの basename が `clamscan` なら `clamscan --version` を実行する
  3. それ以外（独自ラッパー等）はメタデータなし（nil）

  ClamAV の `--version` 出力は
  `ClamAV 1.4.1/27480/Wed Nov  5 08:12:34 2026` 形式。シグネチャ日時は UTC として
  保存する（ClamAV はローカル時刻で出力するため、表示・監査時はその前提で扱う）。
  """

  alias HelpdeskCommander.Attachments.Clamd
  alias HelpdeskCommander.Support.CommandRunner

  @timeout_ms 5_000
  @version_regex ~r/^(?<engine>\S+)\s+(?<version>[^\/\s]+)\/(?<signature>\d+)\/(?<date>.+)$/

  @months %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  @type metadata :: %{
          engine: String.t() | nil,
          version: String.t() | nil,
          signature_at: DateTime.t() | nil
        }

  @doc """
  スキャンエンジンのメタデータを集める。取得できなければすべて nil。

  優先順: 明示の version コマンド → clamd の VERSION → なし。
  """
  @spec collect() :: metadata()
  def collect do
    empty = %{engine: nil, version: nil, signature_at: nil}

    case version_source() do
      nil ->
        empty

      {:command, {command, args}} ->
        case run(command, args) do
          {:ok, output} -> parse(output)
          {:error, _reason} -> empty
        end

      {:clamd, config} ->
        case Clamd.version(config) do
          {:ok, output} -> parse(output)
          {:error, _reason} -> empty
        end
    end
  end

  defp version_source do
    case version_command() do
      nil ->
        case Clamd.default_config() do
          nil -> nil
          config -> {:clamd, config}
        end

      command ->
        {:command, command}
    end
  end

  @doc "`clamscan --version` 形式の出力をパースする。"
  @spec parse(String.t()) :: metadata()
  def parse(output) when is_binary(output) do
    case Regex.named_captures(@version_regex, String.trim(output)) do
      %{"engine" => engine, "version" => version, "date" => date} ->
        %{engine: engine, version: version, signature_at: parse_datetime(date)}

      _no_match ->
        %{engine: nil, version: nil, signature_at: nil}
    end
  end

  defp version_command do
    case Application.get_env(:helpdesk_commander, :attachment_scan_version_command) do
      {command, args} when is_binary(command) and is_list(args) ->
        {command, args}

      command when is_binary(command) ->
        {command, ["--version"]}

      _other ->
        case Application.get_env(:helpdesk_commander, :attachment_scan_command) do
          command when is_binary(command) ->
            if Path.basename(command) == "clamscan", do: {command, ["--version"]}, else: nil

          {command, _args} when is_binary(command) ->
            if Path.basename(command) == "clamscan", do: {command, ["--version"]}, else: nil

          _other ->
            nil
        end
    end
  end

  defp run(command, args) do
    case CommandRunner.run(command, args, timeout: @timeout_ms) do
      {:ok, output, 0} -> {:ok, output}
      {:ok, output, _status} -> {:error, {:exit_status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(date) do
    with [_weekday, month, day, time, year] <- String.split(date),
         month when is_integer(month) <- Map.get(@months, month),
         {day, ""} <- Integer.parse(day),
         {year, ""} <- Integer.parse(year),
         [hour, minute, second] <- String.split(time, ":"),
         {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         {second, ""} <- Integer.parse(second),
         {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second) do
      DateTime.from_naive!(naive, "Etc/UTC")
    else
      _other -> nil
    end
  end
end
