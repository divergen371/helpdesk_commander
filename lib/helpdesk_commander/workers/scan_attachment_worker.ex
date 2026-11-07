defmodule HelpdeskCommander.Workers.ScanAttachmentWorker do
  @moduledoc """
  添付ファイルのウイルススキャンを非同期に実行する（HC-18）。

  - アップロードは `pending` で即時返し、このジョブが隔離ディレクトリの実体を検査する
  - 失敗は上限付き指数バックオフ（15 秒から倍々、最大 5 分）で最大 5 回まで再試行する
  - 同じ添付のジョブは unique 制約で二重実行しない
  - 既に `clean` / `infected` の添付は再実行しても何もしない（冪等）
  """

  use Oban.Worker,
    queue: :attachments,
    max_attempts: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Attachments
  alias HelpdeskCommander.Helpdesk.TicketAttachment
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @max_backoff_seconds 300

  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(attachment_id) do
    %{attachment_id: attachment_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    min(trunc(:math.pow(2, attempt) * 15), @max_backoff_seconds)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => attachment_id}}) do
    case Ash.get(TicketAttachment, attachment_id,
           domain: Helpdesk,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        :ok

      {:ok, %TicketAttachment{scan_status: status}} when status in ["clean", "infected"] ->
        :ok

      {:ok, %TicketAttachment{} = attachment} ->
        run_scan(attachment)

      {:error, error} ->
        ErrorLog.log_error("workers.scan_attachment.load", error, attachment_id: attachment_id)
        {:error, error}
    end
  end

  defp run_scan(attachment) do
    case Attachments.scan_attachment(attachment) do
      {:ok, %TicketAttachment{scan_status: "failed"}} -> {:error, :scan_failed}
      {:ok, %TicketAttachment{}} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
