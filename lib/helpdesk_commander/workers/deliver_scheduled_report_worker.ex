defmodule HelpdeskCommander.Workers.DeliverScheduledReportWorker do
  @moduledoc """
  レポートの定期配信を 1 スケジュールずつ実行する（HC-29）。

  - 失敗は上限付き指数バックオフ（15 秒から倍々、最大 5 分）で最大 5 回まで再試行する
  - 最終失敗は `ReportSchedule.mark_failed` と `ErrorLog` に残る
  """

  use Oban.Worker,
    queue: :reports,
    max_attempts: 5,
    unique: [period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Reports.Scheduled
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @max_backoff_seconds 300

  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(schedule_id) do
    %{schedule_id: schedule_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"schedule_id" => schedule_id}}) do
    case Ash.get(ReportSchedule, schedule_id, domain: Helpdesk, authorize?: false) do
      {:ok, %ReportSchedule{enabled: true} = schedule} ->
        case Scheduled.deliver(schedule) do
          {:ok, _updated} ->
            :ok

          {:error, reason} ->
            ErrorLog.log_error("reports.deliver_scheduled_report", reason, schedule_id: schedule_id)

            {:error, reason}
        end

      {:ok, %ReportSchedule{enabled: false}} ->
        :ok

      {:error, error} ->
        ErrorLog.log_error("reports.deliver_scheduled_report.load", error, schedule_id: schedule_id)

        :error
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    min(trunc(:math.pow(2, attempt - 1) * 15), @max_backoff_seconds)
  end
end
