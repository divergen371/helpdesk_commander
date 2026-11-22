defmodule HelpdeskCommander.Reports.Scheduled do
  @moduledoc """
  定期配信レポートの生成と配信（HC-29）。

  - `Helpdesk.Analytics.summarize/2` の要約を PDF 帳票とテキスト本文にする
  - `channel` が `email` の場合は PDF を添付してメール配信、`chat` は Webhook へ本文を投稿する
  - 成功時は `mark_sent`、失敗時は `mark_failed`（`last_error` に理由を記録）とする
  """

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Analytics
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Reports.Pdf
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @type result :: :ok | {:error, term()}

  @doc "有効なスケジュールのうち、本日配信対象のものを返す。"
  @spec due_schedules(Date.t() | nil) :: {:ok, [ReportSchedule.t()]} | {:error, term()}
  def due_schedules(today \\ Date.utc_today()) do
    weekly_due? = Date.day_of_week(today) == 1

    ReportSchedule
    |> filter(enabled == true)
    |> Ash.read(domain: Helpdesk, authorize?: false)
    |> then(fn
      {:ok, schedules} ->
        {:ok, Enum.filter(schedules, &due?(&1, weekly_due?))}

      {:error, error} ->
        {:error, error}
    end)
  end

  defp due?(%ReportSchedule{period: "daily"}, _weekly_due), do: true
  defp due?(%ReportSchedule{period: "weekly"}, weekly_due), do: weekly_due
  defp due?(%ReportSchedule{}, _weekly_due), do: false

  @doc "スケジュール 1 件のレポートを生成して配信する。"
  @spec deliver(ReportSchedule.t()) :: {:ok, ReportSchedule.t()} | {:error, term()}
  def deliver(%ReportSchedule{} = schedule), do: deliver(schedule, force: false)

  @doc """
  スケジュール 1 件のレポートを生成して配信する。

  `force: true` の場合は同一期間内の送信済みチェックを省略する（「今すぐ送信」用）。
  同一期間内にすでに送信済みの場合は `{:ok, schedule}`（スキップ）を返す。
  """
  @spec deliver(ReportSchedule.t(), keyword()) :: {:ok, ReportSchedule.t()} | {:error, term()}
  def deliver(%ReportSchedule{} = schedule, opts) do
    case check_not_already_sent(schedule, opts) do
      :skip ->
        {:ok, schedule}

      :ok ->
        do_deliver(schedule)
    end
  end

  defp do_deliver(%ReportSchedule{} = schedule) do
    with {:ok, summary} <- Analytics.summarize(schedule.company_id),
         {:ok, _result} <- send_report(schedule, summary),
         {:ok, updated} <- mark(schedule, :mark_sent) do
      {:ok, updated}
    else
      {:error, reason} -> record_failure(schedule, reason)
    end
  end

  defp record_failure(schedule, reason) do
    case mark(schedule, :mark_failed, %{last_error: describe_error(reason)}) do
      {:ok, _failed} ->
        {:error, reason}

      {:error, bookkeeping_error} ->
        ErrorLog.log_error("reports.scheduled.mark_failed", bookkeeping_error, schedule_id: schedule.id)

        {:error, reason}
    end
  end

  defp mark(schedule, action, attrs \\ %{}) do
    schedule
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(domain: Helpdesk, tenant: schedule.company_id, authorize?: false)
  end

  # 同一期間内に送信済みなら配信をスキップする。
  # 通常の重複起票（cron 二重起動・ジョブ重複）に対する保護であり、
  # mark_sent 自体の失敗による再送までは防止しない。
  defp check_not_already_sent(%ReportSchedule{last_sent_at: nil}, _opts), do: :ok
  defp check_not_already_sent(%ReportSchedule{}, force: true), do: :ok

  defp check_not_already_sent(%ReportSchedule{period: period, last_sent_at: last_sent_at}, _opts) do
    today = Date.utc_today()
    sent_date = DateTime.to_date(last_sent_at)

    already? =
      case period do
        "daily" -> Date.compare(sent_date, today) == :eq
        "weekly" -> Date.beginning_of_week(sent_date, :monday) == Date.beginning_of_week(today, :monday)
        _period -> false
      end

    if already?, do: :skip, else: :ok
  end

  defp send_report(%ReportSchedule{channel: "email"} = schedule, summary) do
    if External.email_enabled?() do
      deliver_email(schedule, summary)
    else
      {:error, :email_not_configured}
    end
  end

  defp send_report(%ReportSchedule{channel: "chat"}, summary) do
    if External.chat_enabled?() do
      post_chat(summary)
    else
      {:error, :chat_not_configured}
    end
  end

  defp deliver_email(schedule, summary) do
    recipients = parse_recipients(schedule.recipients)

    if recipients == [] do
      {:error, :no_recipients}
    else
      pdf =
        Pdf.generate(
          "Operations report #{format_period(summary)}",
          pdf_sections(summary)
        )

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to(recipients)
        |> Swoosh.Email.from({"Helpdesk Commander", External.from_email()})
        |> Swoosh.Email.subject("定期レポート（#{format_period(summary)}）")
        |> Swoosh.Email.text_body(text_body(summary))
        |> Swoosh.Email.attachment(
          Swoosh.Attachment.new({:data, pdf},
            filename: "report-#{summary.period.to}.pdf",
            content_type: "application/pdf"
          )
        )

      case HelpdeskCommander.Mailer.deliver(email) do
        {:ok, _email} -> {:ok, :emailed}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp post_chat(summary) do
    options =
      Keyword.merge([json: %{text: summary_text(summary)}, retry: false], External.chat_req_options())

    case Req.post(External.chat_webhook_url(), options) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :posted}

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_recipients(recipients) do
    recipients
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc "Analytics の要約を PDF 帳票の節にする（ASCII のみ、`Reports.Pdf` の制約）。"
  @spec pdf_sections(map()) :: [{String.t(), [String.t()]}]
  def pdf_sections(summary) do
    [
      {"Summary", summary_lines(summary)},
      {"By status", count_lines(summary.by_status)},
      {"By priority (open)", count_lines(summary.by_priority)},
      {"By assignee (open)", assignee_lines(summary.by_assignee, &pdf_assignee_label/1)}
    ]
  end

  @doc "Analytics の要約をチャット投稿用のテキストにする。"
  @spec summary_text(map()) :: String.t()
  def summary_text(summary) do
    [
      {"サマリ", summary_lines(summary)},
      {"ステータス別", count_lines(summary.by_status)},
      {"優先度別（未対応）", count_lines(summary.by_priority)},
      {"担当者別（未対応）", assignee_lines(summary.by_assignee, & &1.key)}
    ]
    |> Enum.flat_map(fn {heading, lines} -> ["■ #{heading}" | lines] end)
    |> Enum.join("\n")
  end

  defp summary_lines(summary) do
    [
      "Period: #{summary.period.from} - #{summary.period.to}",
      "Total tickets: #{summary.total_count}",
      "Open: #{summary.open_count}",
      "Untouched: #{summary.untouched_count}",
      "Stalled (over #{summary.stalled_hours}h): #{summary.stalled_count}",
      "Avg open age (h): #{summary.average_open_age_hours}"
    ]
  end

  defp count_lines([]), do: ["none"]

  defp count_lines(rows) when is_list(rows) do
    Enum.map(rows, fn row -> "#{row.key}: #{row.count}" end)
  end

  defp assignee_lines([], _label_fn), do: ["none"]

  defp assignee_lines(rows, label_fn) when is_list(rows) do
    Enum.map(rows, fn row ->
      "#{label_fn.(row)}: #{row.count} tickets / avg #{row.average_age_hours}h"
    end)
  end

  # PDF は ASCII のみのため、日本語の display_name は user-<id> に置き換える。
  # （チャット・メール本文は UTF-8 でそのまま display_name を使う）
  defp pdf_assignee_label(%{key: nil}), do: "unassigned"

  defp pdf_assignee_label(row) do
    key = to_string(row.key)

    if Pdf.ascii_safe(key) == key do
      key
    else
      "user-#{row.assignee_id}"
    end
  end

  defp text_body(summary), do: summary_text(summary)

  defp format_period(summary), do: "#{summary.period.from} - #{summary.period.to}"

  defp describe_error(reason) do
    reason
    |> inspect(limit: 20)
    |> String.slice(0, 200)
  end
end
