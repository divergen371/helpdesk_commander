defmodule HelpdeskCommanderWeb.AdminReportScheduleLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Notifications.External

  setup do
    original = Application.get_env(:helpdesk_commander, External)
    Application.put_env(:helpdesk_commander, External, email_enabled: true, from_email: "reports@example.com")

    on_exit(fn -> Application.put_env(:helpdesk_commander, External, original) end)

    company = create_company!()
    admin = create_user!(company.id, "admin")
    %{company: company, admin: admin}
  end

  test "admin can create, disable and delete a report schedule", %{conn: conn, company: company, admin: admin} do
    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/report-schedules")

    assert has_element?(view, "#report-schedule-form")
    assert has_element?(view, "#report-schedules", "スケジュールはまだありません")

    view
    |> form("#report-schedule-form", %{
      "schedule" => %{
        "name" => "週次サマリ",
        "period" => "weekly",
        "channel" => "email",
        "recipients" => "ops@example.com"
      }
    })
    |> render_submit()

    assert has_element?(view, "#report-schedules", "週次サマリ")
    assert {:ok, [schedule]} = list_schedules(company)

    view
    |> element("#report-schedule-#{schedule.id} button[phx-value-id='#{schedule.id}'][phx-click='toggle']")
    |> render_click()

    updated = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
    refute updated.enabled

    view
    |> element("#report-schedule-#{schedule.id} button[phx-value-id='#{schedule.id}'][phx-click='delete']")
    |> render_click()

    assert {:ok, []} = list_schedules(company)
  end

  test "send_now registers a delivery job", %{conn: conn, company: company, admin: admin} do
    schedule =
      ReportSchedule
      |> Ash.Changeset.for_create(:create, %{
        name: "即時配信",
        period: "daily",
        channel: "email",
        recipients: "ops@example.com"
      })
      |> Ash.create!(domain: Helpdesk, tenant: company.id, authorize?: false)

    conn = log_in(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/admin/report-schedules")

    assert has_element?(view, "#send-now-#{schedule.id}")

    view
    |> element("#send-now-#{schedule.id}")
    |> render_click()

    assert has_element?(view, "[role=\"alert\"]")

    assert %{success: 1} = Oban.drain_queue(queue: :reports)

    updated = Ash.get!(ReportSchedule, schedule.id, domain: Helpdesk, authorize?: false)
    assert updated.last_sent_at
    refute updated.last_error
  end

  defp list_schedules(company) do
    ReportSchedule
    |> Ash.read(domain: Helpdesk, tenant: company.id, authorize?: false)
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Report UI Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp create_user!(company_id, role) do
    unique = System.unique_integer([:positive])

    HelpdeskCommander.Accounts.User
    |> Ash.Changeset.for_create(:create, %{
      company_id: company_id,
      email: "report-ui-#{unique}@example.com",
      display_name: "Report UI Admin",
      role: role,
      status: "active"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end

  defp log_in(conn, %HelpdeskCommander.Accounts.User{id: user_id}) do
    Plug.Test.init_test_session(conn, %{user_id: user_id})
  end
end
