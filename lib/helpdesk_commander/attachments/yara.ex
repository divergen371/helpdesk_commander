defmodule HelpdeskCommander.Attachments.Yara do
  @moduledoc """
  組織固有の YARA ルール検査（HC-25）。

  `:attachment_yara_command` が設定されているときだけ有効。コマンドが `yara` の場合の
  既定引数は `:attachment_yara_rules`（既定 `priv/yara`）のディレクトリ。カスタム
  ラッパーは `{command, args}` で指定する。

  YARA はマッチの有無にかかわらず終了コード 0 を返すため、検知は標準出力の
  ルール名で判定する。出力が空ならクリーン、1 行以上なら `infected`。
  """

  alias HelpdeskCommander.Support.CommandRunner

  @timeout_ms 10_000
  @default_rules_dir "priv/yara"

  @type scan_result :: {:ok, [String.t()]} | {:error, term()}

  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:helpdesk_commander, :attachment_yara_command) != nil
  end

  @doc "YARA を実行し、一致したルール名を返す。未設定なら空リスト。"
  @spec scan(Path.t()) :: scan_result()
  def scan(path) do
    case command() do
      nil ->
        {:ok, []}

      {command, args} ->
        run(command, List.insert_at(args, -1, path))
    end
  end

  defp command do
    case Application.get_env(:helpdesk_commander, :attachment_yara_command) do
      nil ->
        nil

      {command, args} when is_binary(command) and is_list(args) ->
        {command, args}

      command when is_binary(command) ->
        if Path.basename(command) == "yara" do
          {command, [rules_dir()]}
        else
          {command, []}
        end

      _other ->
        nil
    end
  end

  defp rules_dir do
    Application.get_env(:helpdesk_commander, :attachment_yara_rules) || @default_rules_dir
  end

  defp run(command, args) do
    case CommandRunner.run(command, args, timeout: @timeout_ms) do
      {:ok, output, 0} -> {:ok, rule_names(output)}
      {:ok, output, status} -> {:error, {:exit_status, status, trim(output)}}
      {:error, :timeout} -> {:error, :yara_timeout}
      {:error, reason} -> {:error, {:yara_crash, reason}}
    end
  end

  defp rule_names(output) do
    output
    |> to_string()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      line
      |> String.split()
      |> List.first()
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp trim(output) do
    output
    |> to_string()
    |> String.trim()
    |> String.slice(0, 500)
  end
end
