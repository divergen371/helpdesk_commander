defmodule HelpdeskCommander.Attachments.Clamav do
  @moduledoc """
  ClamAV（clamscan）の深掘り検査設定（HC-23）。

  既定設定のまま実行すると、アーカイブの再帰上限や暗号化ファイルの扱いが
  ClamAV のビルド依存になって検査不能なファイルを黙って通す恐れがある。
  そこで clamscan を指定したときだけ、下記を明示的に付けて実行する。

  - 検査対象の明示: `--scan-archive` / `--scan-pdf` / `--scan-ole2` / `--scan-html`
  - 上限の明示: `--max-scansize` / `--max-filesize` / `--max-recursion` / `--max-files`
    （上限超過は clamscan がエラー扱い → 本アプリの `failed` として隔離）
  - 検査不能の可視化: `--alert-encrypted`（暗号化 ZIP / Office / PDF を感染扱い）と
    `--alert-macros`（OLE2 マクロを感染扱い）→ exit 1（`infected`）として隔離

  上限値の変更は `config :helpdesk_commander, :attachment_scan_clamav` で
  `max_scansize` / `max_filesize` / `max_recursion` / `max_files` を上書きする
  （ClamAV の SIZE 表記 `100M` / `25M`、整数指定可）。
  """

  @default_limits [
    max_scansize: "100M",
    max_filesize: "25M",
    max_recursion: "16",
    max_files: "10000"
  ]

  @target_flags ["--scan-archive=yes", "--scan-pdf=yes", "--scan-ole2=yes", "--scan-html=yes"]

  @alert_flags ["--alert-encrypted=yes", "--alert-macros=yes"]

  @type command_config :: String.t() | {String.t(), [String.t()]}

  @doc "clamscan 用の深掘り検査引数。上限は config の上書き値を優先する。"
  @spec args() :: [String.t()]
  def args do
    overrides = Application.get_env(:helpdesk_commander, :attachment_scan_clamav, []) || []

    limit_flags =
      @default_limits
      |> Keyword.merge(Keyword.take(overrides, limit_keys()))
      |> Enum.map(fn {key, value} -> "--#{key |> Atom.to_string() |> String.replace("_", "-")}=#{value}" end)

    @target_flags ++ limit_flags ++ @alert_flags
  end

  @doc """
  スキャナコマンドの設定値を、clamscan のときだけ深掘り引数つきのタプルへ変換する。
  それ以外のコマンド（任意のラッパー等）はそのまま渡す。
  """
  @spec scan_command(String.t() | nil) :: command_config() | nil
  def scan_command(nil), do: nil

  def scan_command(command) when is_binary(command) do
    if Path.basename(command) == "clamscan" do
      {command, args()}
    else
      command
    end
  end

  defp limit_keys, do: Keyword.keys(@default_limits)
end
