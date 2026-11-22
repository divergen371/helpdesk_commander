defmodule HelpdeskCommander.Workers.DispatchScheduledReportsWorker do
  @moduledoc """
  Cron から起動され、本日配信対象のレポート スケジュールをキューに入れる（HC-29）。

  日次スケジュールは毎日、週次は月曜日（UTC）に配信する。
  """

  use Oban.Worker, queue: :reports, max_attempts: 1

  alias HelpdeskCommander.Reports.Scheduled
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Workers.DeliverScheduledReportWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Scheduled.due_schedules() do
      {:ok, schedules} ->
        _jobs = Enum.map(schedules, &DeliverScheduledReportWorker.enqueue(&1.id))
        :ok

      {:error, error} ->
        ErrorLog.log_error("reports.dispatch_scheduled_reports", error)
        :error
    end
  end
end
