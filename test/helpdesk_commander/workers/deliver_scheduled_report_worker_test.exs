defmodule HelpdeskCommander.Workers.DeliverScheduledReportWorkerTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Workers.DeliverScheduledReportWorker

  setup do
    Cachex.clear(HelpdeskCommander.Cache)

    original_email = Application.get_env(:helpdesk_commander, External)
    Application.put_env(:helpdesk_commander, External, email_enabled: true, from_email: "reports@example.com")

    company = create_company!()

    on_exit(fn ->
      Cachex.clear(HelpdeskCommander.Cache)
      Application.put_env(:helpdesk_commander, External, original_email)
    end)

    %{company: company}
  end

  test "delivers report via email and records success", %{company: company} do
    schedule = create_schedule!(company, "配信OK", "daily", "email", "ops@example.com")

    assert :ok =
             DeliverScheduledReportWorker.perform(%Oban.Job{
               args: %{"schedule_id" => schedule.id, "force" => false},
               attempt: 1
             })

    updated = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
    assert updated.last_sent_at
    refute updated.last_error
  end

  test "returns error when delivery fails so Oban retries", %{company: company} do
    Application.put_env(:helpdesk_commander, External, email_enabled: false)
    schedule = create_schedule!(company, "配信失敗", "daily", "email", "ops@example.com")

    assert {:error, :email_not_configured} =
             DeliverScheduledReportWorker.perform(%Oban.Job{
               args: %{"schedule_id" => schedule.id, "force" => false},
               attempt: 1
             })

    updated = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
    assert updated.last_failed_at
    assert updated.last_error =~ "email_not_configured"
  end

  test "skips disabled schedule without error", %{company: company} do
    schedule = create_schedule!(company, "停止", "daily", "email", "ops@example.com")

    schedule
    |> Ash.Changeset.for_update(:update, %{enabled: false})
    |> Ash.update!(domain: Helpdesk, tenant: company.id, authorize?: false)

    assert :ok =
             DeliverScheduledReportWorker.perform(%Oban.Job{
               args: %{"schedule_id" => schedule.id, "force" => false},
               attempt: 1
             })

    updated = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
    refute updated.last_sent_at
  end

  test "backoff grows exponentially up to max 300 seconds" do
    assert DeliverScheduledReportWorker.backoff(%Oban.Job{attempt: 1}) == 15
    assert DeliverScheduledReportWorker.backoff(%Oban.Job{attempt: 2}) == 30
    assert DeliverScheduledReportWorker.backoff(%Oban.Job{attempt: 10}) == 300
  end

  defp create_schedule!(company, name, period, channel, recipients) do
    ReportSchedule
    |> Ash.Changeset.for_create(:create, %{
      name: name,
      period: period,
      channel: channel,
      recipients: recipients,
      enabled: true
    })
    |> Ash.create!(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Worker Report Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end
end
