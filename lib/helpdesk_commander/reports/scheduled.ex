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
  def deliver(%ReportSchedule{} = schedule) do
    with {:ok, summary} <- Analytics.summarize(schedule.company_id),
         {:ok, _result} <- send_report(schedule, summary) do
      schedule
      |> Ash.Changeset.for_update(:mark_sent, %{})
      |> Ash.update(domain: Helpdesk, tenant: schedule.company_id, authorize?: false)
    else
      {:error, reason} ->
        {:ok, _failed} =
          schedule
          |> Ash.Changeset.for_update(:mark_failed, %{last_error: describe_error(reason)})
          |> Ash.update(domain: Helpdesk, tenant: schedule.company_id, authorize?: false)

        {:error, reason}
    end
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
          "運用レポート #{format_period(summary)}",
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

  @doc "Analytics の要約を PDF 帳票の節にする。"
  @spec pdf_sections(map()) :: [{String.t(), [String.t()]}]
  def pdf_sections(summary) do
    [
      {"サマリ", summary_lines(summary)},
      {"ステータス別", count_lines(summary.by_status)},
      {"優先度別（未対応）", count_lines(summary.by_priority)},
      {"担当者別（未対応）", assignee_lines(summary.by_assignee)}
    ]
  end

  @doc "Analytics の要約をチャット投稿用のテキストにする。"
  @spec summary_text(map()) :: String.t()
  def summary_text(summary) do
    summary
    |> pdf_sections()
    |> Enum.flat_map(fn {heading, lines} -> ["■ #{heading}" | lines] end)
    |> Enum.join("\n")
  end

  defp summary_lines(summary) do
    [
      "期間: #{summary.period.from} 〜 #{summary.period.to}",
      "チケット総数: #{summary.total_count}",
      "未対応: #{summary.open_count}",
      "未着手: #{summary.untouched_count}",
      "滞留（#{summary.stalled_hours}時間超）: #{summary.stalled_count}",
      "平均滞留時間: #{summary.average_open_age_hours}時間"
    ]
  end

  defp count_lines([]), do: ["該当なし"]

  defp count_lines(rows) when is_list(rows) do
    Enum.map(rows, fn row -> "#{row.key}: #{row.count}" end)
  end

  defp assignee_lines([]), do: ["該当なし"]

  defp assignee_lines(rows) when is_list(rows) do
    Enum.map(rows, fn row ->
      "#{row.key}: #{row.count} 件 / 平均 #{row.average_age_hours} 時間"
    end)
  end

  defp text_body(summary), do: summary_text(summary)

  defp format_period(summary), do: "#{summary.period.from}〜#{summary.period.to}"

  defp describe_error(reason) do
    reason
    |> inspect(limit: 20)
    |> String.slice(0, 200)
  end
end
