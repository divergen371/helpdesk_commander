defmodule HelpdeskCommander.Reports.ScheduledTest do
  use HelpdeskCommander.DataCase, async: false

  import Swoosh.TestAssertions

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Reports.Scheduled

  setup do
    Cachex.clear(HelpdeskCommander.Cache)

    original_email = Application.get_env(:helpdesk_commander, External)
    Application.put_env(:helpdesk_commander, External, email_enabled: true, from_email: "reports@example.com")

    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)

    create_ticket!(product, admin, "停電後の接続障害", "in_progress")
    create_ticket!(product, admin, "資料のダウンロード方法", "new")

    on_exit(fn ->
      Cachex.clear(HelpdeskCommander.Cache)
      Application.put_env(:helpdesk_commander, External, original_email)
    end)

    %{company: company, admin: admin, product: product}
  end

  describe "ReportSchedule resource" do
    test "creates a schedule with valid period and channel", %{company: company} do
      schedule = create_schedule!(company, "日次サマリ", "daily", "email", "ops@example.com")
      assert schedule.enabled
      assert schedule.period == "daily"
    end

    test "rejects invalid period and channel", %{company: company} do
      assert {:error, _error} = create_schedule_result(company, "bad", "hourly", "email", "")
      assert {:error, _error} = create_schedule_result(company, "bad", "daily", "sms", "")
    end
  end

  describe "due_schedules/1" do
    test "returns daily schedules every day and weekly schedules on Monday only", %{company: company} do
      _daily = create_schedule!(company, "毎日", "daily", "email", "ops@example.com")
      _weekly = create_schedule!(company, "毎週", "weekly", "email", "ops@example.com")

      monday = ~D[2026-11-16]
      tuesday = ~D[2026-11-17]

      {:ok, due_monday} = Scheduled.due_schedules(monday)
      assert length(due_monday) == 2

      {:ok, due_tuesday} = Scheduled.due_schedules(tuesday)
      assert length(due_tuesday) == 1
      assert hd(due_tuesday).period == "daily"
    end

    test "ignores disabled schedules", %{company: company} do
      schedule = create_schedule!(company, "停止中", "daily", "email", "ops@example.com")

      schedule
      |> Ash.Changeset.for_update(:update, %{enabled: false})
      |> Ash.update!(domain: Helpdesk, tenant: company.id, authorize?: false)

      {:ok, due} = Scheduled.due_schedules(~D[2026-11-16])
      refute Enum.any?(due, &(&1.id == schedule.id))
    end
  end

  describe "deliver/1" do
    test "emails a PDF report and records success", %{company: company} do
      schedule =
        create_schedule!(company, "メール配信", "daily", "email", "ops@example.com, admin@example.com")

      assert {:ok, updated} = Scheduled.deliver(schedule)
      assert updated.last_sent_at
      refute updated.last_error

      assert_received {:email, email}

      assert [attachment] = email.attachments
      assert attachment.filename =~ "report-"
      assert attachment.content_type == "application/pdf"
      assert String.starts_with?(attachment.data, "%PDF-1.4")
      assert email.to == [{"", "ops@example.com"}, {"", "admin@example.com"}]
    end

    test "fails without recipients and records the error", %{company: company} do
      schedule = create_schedule!(company, "宛先なし", "daily", "email", "")

      assert {:error, :no_recipients} = Scheduled.deliver(schedule)

      failed = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
      refute failed.last_sent_at
      assert failed.last_failed_at
      assert failed.last_error =~ "no_recipients"
    end

    test "fails when email channel is not configured" do
      Application.put_env(:helpdesk_commander, External, email_enabled: false)
      company = create_company!()
      schedule = create_schedule!(company, "未設定", "daily", "email", "ops@example.com")

      assert {:error, :email_not_configured} = Scheduled.deliver(schedule)

      failed = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
      assert failed.last_error =~ "email_not_configured"
    end

    test "fails when chat channel is not configured", %{company: company} do
      Application.put_env(:helpdesk_commander, External, chat_enabled: false)
      schedule = create_schedule!(company, "チャット配信", "daily", "chat", "")

      assert {:error, :chat_not_configured} = Scheduled.deliver(schedule)

      failed = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
      assert failed.last_error =~ "chat_not_configured"
    end

    test "chat summary text contains key sections", %{company: _company} do
      summary = build_summary()

      text = Scheduled.summary_text(summary)

      assert text =~ "■ サマリ"
      assert text =~ "Total tickets: 42"
      assert text =~ "■ ステータス別"
      assert text =~ "new: 3"
      assert text =~ "■ 担当者別（未対応）"
    end

    test "pdf sections are ASCII and replace non-ASCII assignee names", %{company: _company} do
      summary = build_summary()

      [summary_section, _status, _priority, assignee_section] = Scheduled.pdf_sections(summary)

      assert {heading, lines} = summary_section
      assert heading == "Summary"
      assert Enum.all?(lines, &(HelpdeskCommander.Reports.Pdf.ascii_safe(&1) == &1))

      assert {assignee_heading, assignee_lines_list} = assignee_section
      assert assignee_heading == "By assignee (open)"
      # 太郎 は日本語のため user-<id> に置き換わる
      assert assignee_lines_list == ["user-101: 5 tickets / avg 8.0h"]
    end

    test "skips delivery when already sent in the current period and does not record failure", %{
      company: company
    } do
      schedule = create_schedule!(company, "送信済み", "daily", "email", "ops@example.com")

      schedule
      |> Ash.Changeset.for_update(:mark_sent, %{})
      |> Ash.update!(domain: Helpdesk, tenant: company.id, authorize?: false)

      assert {:ok, _skipped} = Scheduled.deliver(schedule, force: false)

      skipped = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
      refute skipped.last_failed_at
      refute skipped.last_error
    end

    test "force: true bypasses the already-sent check and delivers", %{company: company} do
      schedule = create_schedule!(company, "強制配信", "daily", "email", "ops@example.com")

      schedule
      |> Ash.Changeset.for_update(:mark_sent, %{})
      |> Ash.update!(domain: Helpdesk, tenant: company.id, authorize?: false)

      assert {:ok, _delivered} = Scheduled.deliver(schedule, force: true)

      assert_email_sent()
    end
  end

  defp build_summary do
    %{
      period: %{from: ~D[2026-11-01], to: ~D[2026-11-30]},
      total_count: 42,
      open_count: 10,
      untouched_count: 3,
      stalled_count: 2,
      average_open_age_hours: 12.5,
      stalled_hours: 24,
      by_status: [%{key: "new", count: 3}, %{key: "in_progress", count: 7}],
      by_priority: [%{key: "p2", count: 4}],
      by_assignee: [%{key: "太郎", assignee_id: 101, count: 5, average_age_hours: 8.0}]
    }
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

  defp create_schedule_result(company, name, period, channel, recipients) do
    ReportSchedule
    |> Ash.Changeset.for_create(:create, %{
      name: name,
      period: period,
      channel: channel,
      recipients: recipients,
      enabled: true
    })
    |> Ash.create(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Report Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_user!(company_id, role) do
    unique = System.unique_integer([:positive])

    HelpdeskCommander.Accounts.User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      email: "report-#{role}-#{unique}@example.com",
      display_name: "Report #{role}",
      role: role,
      status: "active"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_product!(company) do
    unique = System.unique_integer([:positive])

    Product
    |> Ash.Changeset.for_create(:create, %{
      company_id: company.id,
      name: "Product #{unique}"
    })
    |> Ash.create!(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_ticket!(product, requester, subject, status) do
    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        company_id: product.company_id,
        product_id: product.id,
        requester_id: requester.id,
        subject: subject,
        description: "HC-29 report test",
        type: "question",
        impact: "minor",
        urgency: "low"
      })
      |> Ash.create!(domain: Helpdesk, tenant: product.company_id, actor: requester)

    if status != "new" do
      ticket
      |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: requester.id})
      |> Ash.update!(domain: Helpdesk, tenant: product.company_id, actor: requester)
    else
      ticket
    end
  end
end
