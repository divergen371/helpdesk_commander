defmodule HelpdeskCommanderWeb.DashboardLive do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Analytics
  alias HelpdeskCommander.Helpdesk.Notifications
  alias HelpdeskCommander.Helpdesk.Sla
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)
    company_id = current_user.company_id

    {ticket_count, recent_tickets} = load_tickets(company_id, current_user, external_user?)
    {task_count, recent_tasks} = load_tasks(company_id, external_user?, current_user)
    product_count = load_product_count(company_id, external_user?)
    unread_count = load_unread_count(current_user, external_user?)
    sla_breaches = load_sla_breaches(company_id, external_user?)
    {analytics, analytics_form} = load_analytics(company_id, external_user?, nil)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:ticket_count, ticket_count)
     |> assign(:task_count, task_count)
     |> assign(:product_count, product_count)
     |> assign(:unread_count, unread_count)
     |> assign(:sla_breaches, sla_breaches)
     |> assign(:analytics, analytics)
     |> assign(:analytics_form, analytics_form)
     |> assign(:recent_tickets, recent_tickets)
     |> assign(:recent_tasks, recent_tasks)}
  end

  defp load_tickets(company_id, current_user, external_user?) do
    with {:ok, count} <- Helpdesk.count_tickets(company_id, current_user, external_user?),
         {:ok, tickets} <-
           Helpdesk.list_recent_tickets(company_id, current_user, external_user?, 5) do
      {count, tickets}
    else
      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_tickets", error)
        {0, []}
    end
  end

  defp load_tasks(company_id, false, current_user) do
    with {:ok, count} <- Tasks.count_tasks(company_id, actor: current_user),
         {:ok, tasks} <- Tasks.list_recent_tasks(company_id, 5, actor: current_user) do
      {count, tasks}
    else
      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_tasks", error)
        {0, []}
    end
  end

  defp load_tasks(_company_id, true, _current_user), do: {0, []}

  defp load_product_count(company_id, false) do
    case Helpdesk.count_active_products(company_id) do
      {:ok, count} ->
        count

      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_products", error)
        0
    end
  end

  defp load_product_count(_company_id, true), do: 0

  defp load_unread_count(current_user, false) do
    case Notifications.unread_count(current_user) do
      {:ok, count} ->
        count

      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_notifications", error)
        0
    end
  end

  defp load_unread_count(_current_user, true), do: 0

  defp load_sla_breaches(company_id, false) do
    case Sla.breached_tickets(company_id, 5) do
      {:ok, breaches} ->
        breaches

      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_sla_breaches", error)
        []
    end
  end

  defp load_sla_breaches(_company_id, true), do: []

  defp load_analytics(_company_id, true, _params), do: {nil, nil}

  defp load_analytics(company_id, false, params) do
    {from, to} = analytics_period(params)

    case Analytics.summarize(company_id, from: from, to: to) do
      {:ok, summary} ->
        {summary, analytics_form(from, to)}

      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_analytics", error)

        {empty_summary(from, to), analytics_form(from, to)}
    end
  end

  defp analytics_period(nil) do
    Analytics.default_period()
  end

  defp analytics_period(%{"from" => from_value, "to" => to_value}) do
    with {:ok, from} <- Date.from_iso8601(from_value),
         {:ok, to} <- Date.from_iso8601(to_value),
         true <- Date.compare(from, to) != :gt do
      {from, to}
    else
      _error -> Analytics.default_period()
    end
  end

  defp analytics_period(_params), do: Analytics.default_period()

  defp analytics_form(from, to) do
    to_form(%{"from" => Date.to_iso8601(from), "to" => Date.to_iso8601(to)}, as: "analytics")
  end

  defp empty_summary(from, to) do
    %{
      period: %{from: from, to: to},
      stalled_hours: Analytics.default_stalled_hours(),
      total_count: 0,
      open_count: 0,
      untouched_count: 0,
      stalled_count: 0,
      average_open_age_hours: 0.0,
      by_status: [],
      by_priority: [],
      by_assignee: []
    }
  end

  defp breached_metric_labels(metrics) do
    metrics
    |> Enum.filter(&(&1.status == :breached))
    |> Enum.map_join(" / ", & &1.label)
  end

  @impl Phoenix.LiveView
  def handle_event("filter_analytics", %{"analytics" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case parse_analytics_period(params) do
        {:ok, _period} ->
          {analytics, form} = load_analytics(socket.assigns.current_user.company_id, false, params)

          {:noreply,
           socket
           |> assign(:analytics, analytics)
           |> assign(:analytics_form, form)}

        :error ->
          {:noreply, put_flash(socket, :error, "期間の指定が正しくありません")}
      end
    end
  end

  defp parse_analytics_period(%{"from" => from_value, "to" => to_value}) do
    with {:ok, from} <- Date.from_iso8601(from_value),
         {:ok, to} <- Date.from_iso8601(to_value),
         true <- Date.compare(from, to) != :gt do
      {:ok, {from, to}}
    else
      _error -> :error
    end
  end

  defp parse_analytics_period(_params), do: :error

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <section class="overflow-hidden rounded-3xl border border-base-200 bg-gradient-to-br from-primary/15 via-base-100 to-base-200/60 p-8 sm:p-10">
        <p class="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
          Helpdesk Commander
        </p>
        <h1 class="mt-3 text-3xl font-bold tracking-tight sm:text-4xl">
          今日の運用を、ひと目で。
        </h1>
        <p class="mt-3 max-w-2xl text-sm leading-6 opacity-70">
          問い合わせ、チケット、タスク、製品、通知を一か所に集約しています。
        </p>
        <div class="mt-6 flex flex-wrap gap-3">
          <.link class="btn btn-primary" navigate={~p"/inquiries/new"}>
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> 問い合わせ
          </.link>
          <.link class="btn" navigate={~p"/tickets"}>
            <.icon name="hero-ticket" class="size-4" /> チケット一覧
          </.link>
          <%= if !@current_user_external? do %>
            <.link class="btn" navigate={~p"/tasks/new"}>
              <.icon name="hero-plus" class="size-4" /> タスク作成
            </.link>
            <.link class="btn" navigate={~p"/relations"}>
              <.icon name="hero-share" class="size-4" /> 関係グラフ
            </.link>
          <% end %>
        </div>
      </section>

      <section class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <.stat_card label="チケット" value={@ticket_count} href={~p"/tickets"} />
        <%= if !@current_user_external? do %>
          <.stat_card label="タスク" value={@task_count} href={~p"/tasks"} />
          <.stat_card label="有効な製品" value={@product_count} href={~p"/products"} />
          <.stat_card label="未読通知" value={@unread_count} href={~p"/notifications"} />
          <.stat_card label="SLA 逸脱" value={length(@sla_breaches)} href={~p"/settings/sla"} />
        <% else %>
          <.stat_card label="未読通知" value={@unread_count} href={~p"/notifications"} />
        <% end %>
      </section>

      <section
        :if={!@current_user_external?}
        id="sla-breaches"
        class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 class="font-semibold">SLA 逸脱</h2>
            <p class="mt-1 text-sm opacity-60">
              未クローズのチケットで、いずれかの目標時間を過ぎている件数です。
            </p>
          </div>
          <.link class="link text-sm" navigate={~p"/settings/sla"}>SLA 設定</.link>
        </div>

        <p class="mt-4 text-3xl font-bold tabular-nums">{length(@sla_breaches)}</p>

        <div :if={@sla_breaches == []} class="mt-2 text-sm opacity-70">
          逸脱しているチケットはありません。
        </div>
        <div :if={@sla_breaches != []} class="mt-4 space-y-2">
          <.link
            :for={breach <- @sla_breaches}
            id={"sla-breach-#{breach.ticket.id}"}
            navigate={~p"/tickets/#{breach.ticket.public_id}"}
            class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-base-200 px-3 py-2 text-sm transition hover:bg-base-200/40"
          >
            <span class="font-medium">{breach.ticket.public_id} {breach.ticket.subject}</span>
            <span class="text-xs text-error">{breached_metric_labels(breach.metrics)}</span>
          </.link>
        </div>
      </section>

      <section
        :if={!@current_user_external?}
        id="analytics"
        class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h2 class="font-semibold">分析</h2>
            <p class="mt-1 text-sm opacity-60">
              期間内に作成されたチケットの未対応・滞留・担当者別負荷です。
            </p>
          </div>
          <.link
            href={"/reports/analytics.csv?from=#{@analytics.period.from}&to=#{@analytics.period.to}"}
            class="btn btn-sm"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> CSV
          </.link>
        </div>

        <.form
          for={@analytics_form}
          id="analytics-form"
          phx-submit="filter_analytics"
          class="mt-4 flex flex-wrap items-end gap-3"
        >
          <.input field={@analytics_form[:from]} type="date" label="開始日" />
          <.input field={@analytics_form[:to]} type="date" label="終了日" />
          <.button type="submit">集計</.button>
        </.form>

        <div class="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-5">
          <div class="rounded-xl border border-base-200 p-3">
            <p class="text-xs opacity-60">期間内作成</p>
            <p class="mt-1 text-2xl font-bold tabular-nums">{@analytics.total_count}</p>
          </div>
          <div class="rounded-xl border border-base-200 p-3">
            <p class="text-xs opacity-60">未対応</p>
            <p class="mt-1 text-2xl font-bold tabular-nums">{@analytics.open_count}</p>
          </div>
          <div class="rounded-xl border border-base-200 p-3">
            <p class="text-xs opacity-60">未着手</p>
            <p class="mt-1 text-2xl font-bold tabular-nums">{@analytics.untouched_count}</p>
          </div>
          <div class="rounded-xl border border-base-200 p-3">
            <p class="text-xs opacity-60">滞留（{@analytics.stalled_hours}h超）</p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-error">{@analytics.stalled_count}</p>
          </div>
          <div class="rounded-xl border border-base-200 p-3">
            <p class="text-xs opacity-60">平均滞留</p>
            <p class="mt-1 text-2xl font-bold tabular-nums">{@analytics.average_open_age_hours}h</p>
          </div>
        </div>

        <div class="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-2">
          <div>
            <h3 class="font-semibold">担当者別負荷</h3>
            <div :if={@analytics.by_assignee == []} class="mt-2 text-sm opacity-70">
              未対応のチケットはありません。
            </div>
            <table :if={@analytics.by_assignee != []} class="mt-2 w-full text-sm">
              <thead>
                <tr class="text-left text-xs opacity-60">
                  <th class="py-1">担当者</th>
                  <th class="py-1 text-right">未対応</th>
                  <th class="py-1 text-right">平均滞留</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @analytics.by_assignee} class="border-t border-base-200">
                  <td class="py-2">{row.key}</td>
                  <td class="py-2 text-right tabular-nums">{row.count}</td>
                  <td class="py-2 text-right tabular-nums">{row.average_age_hours}h</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2">
            <div>
              <h3 class="font-semibold">状態別</h3>
              <div :if={@analytics.by_status == []} class="mt-2 text-sm opacity-70">データなし</div>
              <ul class="mt-2 space-y-1 text-sm">
                <li :for={row <- @analytics.by_status} class="flex justify-between border-t border-base-200 py-1">
                  <span>{row.key}</span>
                  <span class="tabular-nums">{row.count}</span>
                </li>
              </ul>
            </div>
            <div>
              <h3 class="font-semibold">優先度別（未対応）</h3>
              <div :if={@analytics.by_priority == []} class="mt-2 text-sm opacity-70">データなし</div>
              <ul class="mt-2 space-y-1 text-sm">
                <li :for={row <- @analytics.by_priority} class="flex justify-between border-t border-base-200 py-1">
                  <span>{row.key}</span>
                  <span class="tabular-nums">{row.count}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <section class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">最近のチケット</h2>
            <.link class="link text-sm" navigate={~p"/tickets"}>すべて見る</.link>
          </div>

          <div class="mt-4 space-y-3">
            <div :if={@recent_tickets == []} class="text-sm opacity-70">
              チケットはまだありません。
            </div>
            <.link
              :for={ticket <- @recent_tickets}
              navigate={~p"/tickets/#{ticket.public_id}"}
              class="flex items-center justify-between gap-3 rounded-xl border border-base-200 p-3 transition hover:bg-base-200/40"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium">{ticket.subject}</p>
                <p class="mt-1 text-xs opacity-60">
                  {ticket.public_id} · {ticket.product && ticket.product.name}
                </p>
              </div>
              <div class="flex shrink-0 gap-2 text-xs">
                <span class="rounded-full bg-base-200 px-2 py-1">{ticket.status}</span>
                <span class="rounded-full bg-base-200 px-2 py-1">{ticket.priority}</span>
              </div>
            </.link>
          </div>
        </section>

        <section
          :if={!@current_user_external?}
          class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm"
        >
          <div class="flex items-center justify-between">
            <h2 class="font-semibold">最近のタスク</h2>
            <.link class="link text-sm" navigate={~p"/tasks"}>すべて見る</.link>
          </div>

          <div class="mt-4 space-y-3">
            <div :if={@recent_tasks == []} class="text-sm opacity-70">
              タスクはまだありません。
            </div>
            <.link
              :for={task <- @recent_tasks}
              navigate={~p"/tasks/#{task.public_id}"}
              class="flex items-center justify-between gap-3 rounded-xl border border-base-200 p-3 transition hover:bg-base-200/40"
            >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium">{task.title}</p>
                <p class="mt-1 text-xs opacity-60">
                  {task.public_id} · {task.due_date || "期限なし"}
                </p>
              </div>
              <div class="flex shrink-0 gap-2 text-xs">
                <span class="rounded-full bg-base-200 px-2 py-1">{task.status}</span>
                <span class="rounded-full bg-base-200 px-2 py-1">{task.priority}</span>
              </div>
            </.link>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :href, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="rounded-2xl border border-base-200 bg-base-100 p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
    >
      <p class="text-xs uppercase tracking-wide opacity-60">{@label}</p>
      <p class="mt-2 text-3xl font-bold tabular-nums">{@value}</p>
    </.link>
    """
  end
end
