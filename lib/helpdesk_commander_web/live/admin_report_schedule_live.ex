defmodule HelpdeskCommanderWeb.AdminReportScheduleLive do
  @moduledoc """
  レポートの定期配信スケジュールを管理する管理者向け画面（HC-29）。
  """

  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ReportSchedule
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Workers.DeliverScheduledReportWorker
  @empty_form %{"name" => "", "period" => "daily", "channel" => "email", "recipients" => ""}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_user.company_id

    {:ok,
     socket
     |> assign(:page_title, "定期レポート配信")
     |> assign(:form, to_form(@empty_form, as: "schedule"))
     |> assign(:company_id, company_id)
     |> load_schedules()}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"schedule" => params}, socket) do
    attrs = %{
      name: String.trim(params["name"] || ""),
      period: params["period"],
      channel: params["channel"],
      recipients: String.trim(params["recipients"] || ""),
      enabled: true
    }

    case ReportSchedule
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create(domain: Helpdesk, tenant: socket.assigns.company_id, authorize?: false) do
      {:ok, _schedule} ->
        {:noreply,
         socket
         |> put_flash(:info, "配信スケジュールを保存しました")
         |> assign(:form, to_form(@empty_form, as: "schedule"))
         |> load_schedules()}

      {:error, error} ->
        ErrorLog.log_error("admin_report_schedule.save", error)
        {:noreply, put_flash(socket, :error, "配信スケジュールの保存に失敗しました")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle", %{"id" => id}, socket) do
    schedule = Enum.find(socket.assigns.schedules, &(to_string(&1.id) == id))

    case schedule && update_enabled(schedule, not schedule.enabled) do
      {:ok, _updated} ->
        {:noreply, socket |> put_flash(:info, "配信設定を更新しました") |> load_schedules()}

      _error ->
        {:noreply, put_flash(socket, :error, "配信設定の更新に失敗しました")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    schedule = Enum.find(socket.assigns.schedules, &(to_string(&1.id) == id))

    case schedule && Ash.destroy(schedule, domain: Helpdesk, authorize?: false) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "配信スケジュールを削除しました") |> load_schedules()}

      _error ->
        {:noreply, put_flash(socket, :error, "配信スケジュールの削除に失敗しました")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("send_now", %{"id" => id}, socket) do
    enqueue_result = id |> String.to_integer() |> DeliverScheduledReportWorker.enqueue()

    case enqueue_result do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "配信ジョブを登録しました")}

      {:error, error} ->
        ErrorLog.log_error("admin_report_schedule.send_now", error)
        {:noreply, put_flash(socket, :error, "配信ジョブの登録に失敗しました")}
    end
  end

  defp update_enabled(schedule, enabled) do
    schedule
    |> Ash.Changeset.for_update(:update, %{enabled: enabled})
    |> Ash.update(domain: Helpdesk, tenant: schedule.company_id, authorize?: false)
  end

  defp load_schedules(socket) do
    case ReportSchedule
         |> filter(company_id == ^socket.assigns.company_id)
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.read(domain: Helpdesk, tenant: socket.assigns.company_id, authorize?: false) do
      {:ok, schedules} ->
        assign(socket, :schedules, schedules)

      {:error, error} ->
        ErrorLog.log_error("admin_report_schedule.load", error)
        assign(socket, :schedules, [])
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        定期レポート配信
        <:subtitle>日次/週次で運用レポートをメールまたはチャットへ配信します</:subtitle>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@form} id="report-schedule-form" phx-submit="save" class="grid gap-4 sm:grid-cols-2">
            <.input field={@form[:name]} label="名前" placeholder="例: 週次サマリ" required />
            <.input
              field={@form[:period]}
              type="select"
              label="周期"
              options={[{"日次", "daily"}, {"週次（月曜）", "weekly"}]}
            />
            <.input
              field={@form[:channel]}
              type="select"
              label="配信先"
              options={[{"メール（PDF 添付）", "email"}, {"チャット Webhook", "chat"}]}
            />
            <.input
              field={@form[:recipients]}
              label="宛先（メールはカンマ区切り）"
              placeholder="ops@example.com, admin@example.com"
            />
            <div class="sm:col-span-2">
              <.button type="submit">追加</.button>
            </div>
          </.form>
        </div>
      </div>

      <div id="report-schedules" class="mt-6 card bg-base-100 border border-base-200">
        <div class="card-body">
          <div :if={@schedules == []} class="text-sm opacity-70">スケジュールはまだありません。</div>

          <div :for={schedule <- @schedules} id={"report-schedule-#{schedule.id}"} class="border-b border-base-200 py-3">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p class="font-medium">{schedule.name}</p>
                <p class="text-sm opacity-70">
                  {period_label(schedule.period)} / {channel_label(schedule.channel)} / {if schedule.enabled,
                    do: "有効",
                    else: "無効"}
                </p>
                <p
                  :if={schedule.last_error}
                  id={"report-schedule-error-#{schedule.id}"}
                  class="text-sm text-error"
                >
                  最終エラー: {schedule.last_error}
                </p>
              </div>

              <div class="flex gap-2">
                <.button
                  id={"send-now-#{schedule.id}"}
                  type="button"
                  phx-click="send_now"
                  phx-value-id={schedule.id}
                >
                  今すぐ送信
                </.button>
                <.button
                  type="button"
                  phx-click="toggle"
                  phx-value-id={schedule.id}
                  variant={if schedule.enabled, do: nil, else: "primary"}
                >
                  {if schedule.enabled, do: "無効にする", else: "有効にする"}
                </.button>
                <.button type="button" phx-click="delete" phx-value-id={schedule.id}>
                  削除
                </.button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp period_label("weekly"), do: "週次"
  defp period_label(_period), do: "日次"
  defp channel_label("chat"), do: "チャット"
  defp channel_label(_channel), do: "メール"
end
