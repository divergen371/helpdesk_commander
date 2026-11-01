defmodule HelpdeskCommanderWeb.TaskLive.Index do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommanderWeb.CurrentUser
  alias HelpdeskCommanderWeb.FormOptions

  @statuses ~w(todo in_progress done)
  @priorities ~w(low medium high)
  @sorts ~w(newest oldest priority status due_date)

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)

    {assignees, socket} =
      case FormOptions.load_internal_users(current_user) do
        {:ok, assignees} ->
          {assignees, socket}

        {:error, error} ->
          ErrorLog.log_error("task_live.index.load_assignees", error)

          {[], put_flash(socket, :error, "担当者一覧の取得に失敗しました")}
      end

    {:ok,
     socket
     |> assign(:page_title, "Tasks")
     |> assign(:current_user, current_user)
     |> assign(:assignees, assignees)
     |> assign(:filters, default_filters())
     |> assign(:filter_form, filter_form(default_filters()))
     |> stream(:tasks, [], dom_id: &"task-#{&1.public_id}")}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    socket =
      case load_tasks(socket.assigns.current_user, filters) do
        {:ok, tasks} ->
          socket
          |> assign(:filters, filters)
          |> assign(:filter_form, filter_form(filters))
          |> stream(:tasks, tasks, reset: true, dom_id: &"task-#{&1.public_id}")

        {:error, error} ->
          ErrorLog.log_error("task_live.index.load_tasks", error, user_id: CurrentUser.id(socket.assigns.current_user))

          socket
          |> assign(:filters, filters)
          |> assign(:filter_form, filter_form(filters))
          |> stream(:tasks, [], reset: true, dom_id: &"task-#{&1.public_id}")
          |> put_flash(:error, "タスクの取得に失敗しました")
      end

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"filters" => params}, socket) do
    params =
      params
      |> reject_blank()
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/tasks?#{params}")}
  end

  defp load_tasks(%{company_id: company_id} = current_user, filters) do
    Tasks.list_tasks(company_id, actor: current_user, filters: filters)
  end

  defp load_tasks(_current_user, _filters), do: {:ok, []}

  defp default_filters do
    %{q: nil, status: nil, priority: nil, assignee_id: nil, sort: "newest"}
  end

  defp filter_form(filters) do
    params = Map.new(filters, fn {key, value} -> {to_string(key), value} end)
    to_form(params, as: "filters")
  end

  defp parse_filters(params) do
    %{
      q: normalize_search(params["q"]),
      status: allow(params["status"], @statuses),
      priority: allow(params["priority"], @priorities),
      assignee_id: normalize_assignee(params["assignee_id"]),
      sort: allow(params["sort"], @sorts) || "newest"
    }
  end

  defp normalize_search(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 100)
    end
  end

  defp normalize_search(_value), do: nil

  defp allow(value, allowed) do
    if value in allowed, do: value, else: nil
  end

  defp normalize_assignee("unassigned"), do: "unassigned"
  defp normalize_assignee(nil), do: nil
  defp normalize_assignee(""), do: nil

  defp normalize_assignee(value) do
    case Integer.parse(value) do
      {_id, _rest} -> value
      :error -> nil
    end
  end

  defp reject_blank(params) do
    Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)
  end

  defp status_options, do: Enum.map(@statuses, &{&1, &1})
  defp priority_options, do: Enum.map(@priorities, &{&1, &1})

  defp assignee_options(assignees) do
    [{"未割り当て", "unassigned"} | FormOptions.user_options(assignees)]
  end

  defp sort_options do
    [
      {"新しい順", "newest"},
      {"古い順", "oldest"},
      {"優先度順", "priority"},
      {"ステータス順", "status"},
      {"期限が近い順", "due_date"}
    ]
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        Tasks
        <:subtitle>タスクの一覧</:subtitle>
        <:actions>
          <.button navigate={~p"/tasks/new"} variant="primary">
            <.icon name="hero-plus" class="size-4" /> 新規作成
          </.button>
          <.button navigate={~p"/tickets"}>
            Tickets
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@filter_form} id="task-filters" phx-change="filter">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
              <.input field={@filter_form[:q]} type="search" label="検索" placeholder="タイトル" />
              <.input
                field={@filter_form[:status]}
                type="select"
                label="ステータス"
                prompt="すべて"
                options={status_options()}
              />
              <.input
                field={@filter_form[:priority]}
                type="select"
                label="優先度"
                prompt="すべて"
                options={priority_options()}
              />
              <.input
                field={@filter_form[:assignee_id]}
                type="select"
                label="担当者"
                prompt="すべて"
                options={assignee_options(@assignees)}
              />
              <.input
                field={@filter_form[:sort]}
                type="select"
                label="並び順"
                options={sort_options()}
              />
            </div>
          </.form>
        </div>
      </div>

      <div class="rounded-2xl border border-base-200 bg-base-100 shadow-sm">
        <div id="tasks" phx-update="stream" class="divide-y divide-base-200">
          <div id="tasks-empty" class="hidden only:block p-6 text-sm opacity-70">
            タスクはまだありません。
          </div>

          <div
            :for={{id, task} <- @streams.tasks}
            id={id}
            class="grid gap-3 p-4 transition hover:bg-base-200/40 sm:grid-cols-[1fr_auto]"
          >
            <div>
              <.link class="font-medium hover:underline" navigate={~p"/tasks/#{task.public_id}"}>
                {task.title}
              </.link>
              <div class="mt-1 text-xs opacity-60">{task.public_id}</div>
            </div>
            <div class="flex items-center gap-3 text-sm">
              <span class="rounded-full bg-base-200 px-3 py-1">{task.status}</span>
              <span class="rounded-full bg-base-200 px-3 py-1">{task.priority}</span>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
