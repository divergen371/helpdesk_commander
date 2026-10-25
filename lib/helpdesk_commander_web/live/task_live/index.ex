defmodule HelpdeskCommanderWeb.TaskLive.Index do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)

    {tasks, socket} =
      case load_tasks(current_user) do
        {:ok, tasks} ->
          {tasks, socket}

        {:error, error} ->
          ErrorLog.log_error("task_live.index.load_tasks", error, user_id: CurrentUser.id(current_user))
          {[], put_flash(socket, :error, "タスクの取得に失敗しました")}
      end

    {:ok,
     socket
     |> assign(:page_title, "Tasks")
     |> assign(:current_user, current_user)
     |> stream(:tasks, tasks, dom_id: &"task-#{&1.public_id}")}
  end

  defp load_tasks(%{company_id: company_id}) do
    Task
    |> filter(company_id == ^company_id)
    |> sort(inserted_at: :desc)
    |> Ash.read(domain: Tasks)
  end

  defp load_tasks(_current_user), do: {:ok, []}

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
