defmodule HelpdeskCommander.Workers.UpdateSignaturesWorker do
  @moduledoc """
  スキャナシグネチャの更新を定期実行する（HC-22）。

  - `:attachment_signature_update_command`（例: `freshclam`）を実行する
  - 成功時は `ScanMetadata` からエンジン・版・シグネチャ日時を取り出して
    `AttachmentSignature` に保存し、既存の clean / skipped 添付を再スキャンする
  - 失敗時は状態を `error` として保存し、Oban の再試行に委ねる
  - 更新コマンド未設定（開発・テスト）は何もしない
  """

  use Oban.Worker,
    queue: :attachments,
    max_attempts: 3

  alias HelpdeskCommander.Attachments.ScanMetadata
  alias HelpdeskCommander.Attachments.Signatures
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Support.CommandRunner
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  require Logger

  @timeout_ms 300_000

  @spec enqueue() :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue do
    %{}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(_job) do
    case update_command() do
      nil ->
        :ok

      {command, args} ->
        run_update(command, args)
    end
  end

  defp run_update(command, args) do
    case run(command, args) do
      {:ok, _output} ->
        record_success()
        rescan_outdated()
        :ok

      {:error, reason} = error ->
        record_error(reason)
        error
    end
  end

  defp run(command, args) do
    case CommandRunner.run(command, args, timeout: @timeout_ms) do
      {:ok, output, 0} -> {:ok, output}
      {:ok, output, status} -> {:error, {:exit_status, status, trim(output)}}
      {:error, :timeout} -> {:error, :update_timeout}
      {:error, reason} -> {:error, {:update_crash, reason}}
    end
  end

  defp record_success do
    metadata = ScanMetadata.collect()

    case Signatures.record(%{
           engine: metadata.engine,
           version: metadata.version,
           signature_at: metadata.signature_at,
           checked_at: DateTime.utc_now(),
           status: "ok",
           last_error: nil
         }) do
      {:ok, _signature} -> :ok
      {:error, error} -> ErrorLog.log_error("workers.update_signatures.record", error)
    end
  end

  defp record_error(reason) do
    case Signatures.record(%{
           checked_at: DateTime.utc_now(),
           status: "error",
           last_error: inspect(reason)
         }) do
      {:ok, _signature} -> :ok
      {:error, error} -> ErrorLog.log_error("workers.update_signatures.record_error", error)
    end
  end

  defp rescan_outdated do
    stats = Attachments.rescan_outdated()

    if stats.enqueued > 0 or stats.failed > 0 do
      Logger.info("attachment rescan after signature update: #{inspect(stats)}")
    end

    :ok
  end

  defp update_command do
    case Application.get_env(:helpdesk_commander, :attachment_signature_update_command) do
      {command, args} when is_binary(command) and is_list(args) -> {command, args}
      command when is_binary(command) -> {command, []}
      _other -> nil
    end
  end

  defp trim(output) do
    output
    |> to_string()
    |> String.trim()
    |> String.slice(0, 500)
  end
end
