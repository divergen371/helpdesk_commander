defmodule HelpdeskCommanderWeb.DashboardLive do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Notifications
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)
    company_id = current_user.company_id

    {ticket_count, recent_tickets} = load_tickets(company_id, current_user, external_user?)
    {task_count, recent_tasks} = load_tasks(company_id, external_user?)
    product_count = load_product_count(company_id, external_user?)
    unread_count = load_unread_count(current_user, external_user?)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:ticket_count, ticket_count)
     |> assign(:task_count, task_count)
     |> assign(:product_count, product_count)
     |> assign(:unread_count, unread_count)
     |> assign(:recent_tickets, recent_tickets)
     |> assign(:recent_tasks, recent_tasks)}
  end

  defp load_tickets(company_id, current_user, external_user?) do
    query =
      Ticket
      |> filter(company_id == ^company_id or visibility_scope == "global")
      |> maybe_filter_external(current_user, external_user?)

    recent_query = query |> sort(inserted_at: :desc) |> Ash.Query.limit(5)

    with {:ok, count} <- Ash.count(query, domain: Helpdesk),
         {:ok, tickets} <- Ash.read(recent_query, domain: Helpdesk),
         {:ok, tickets} <- Ash.load(tickets, [:product], domain: Helpdesk) do
      {count, tickets}
    else
      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_tickets", error)
        {0, []}
    end
  end

  defp maybe_filter_external(query, %User{id: id}, true), do: filter(query, requester_id == ^id)
  defp maybe_filter_external(query, _user, _external), do: query

  defp load_tasks(company_id, false) do
    query = filter(Task, company_id == ^company_id)

    recent_query = query |> sort(inserted_at: :desc) |> Ash.Query.limit(5)

    with {:ok, count} <- Ash.count(query, domain: Tasks),
         {:ok, tasks} <- Ash.read(recent_query, domain: Tasks) do
      {count, tasks}
    else
      {:error, error} ->
        ErrorLog.log_error("dashboard_live.load_tasks", error)
        {0, []}
    end
  end

  defp load_tasks(_company_id, true), do: {0, []}

  defp load_product_count(company_id, false) do
    query = filter(Product, company_id == ^company_id and active == true)

    case Ash.count(query, domain: Helpdesk) do
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
        <% else %>
          <.stat_card label="未読通知" value={@unread_count} href={~p"/notifications"} />
        <% end %>
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

        <section :if={!@current_user_external?} class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
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
