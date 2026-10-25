defmodule HelpdeskCommanderWeb.TaskLive.Show do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommander.Tasks.TaskEvent
  alias HelpdeskCommanderWeb.CurrentUser
  alias HelpdeskCommanderWeb.FormOptions

  @impl Phoenix.LiveView
  def mount(%{"public_id" => public_id}, session, socket) do
    current_user = CurrentUser.fetch(session)

    {assignees, socket} =
      case FormOptions.load_internal_users(current_user) do
        {:ok, assignees} ->
          {assignees, socket}

        {:error, error} ->
          ErrorLog.log_error("task_live.show.load_assignees", error)

          {[], put_flash(socket, :error, "担当者一覧の取得に失敗しました")}
      end

    case load_task_data(public_id, current_user) do
      {:ok, data} ->
        {:ok, assign_task_socket(socket, data, current_user, assignees)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "タスクが見つかりません")
         |> push_navigate(to: ~p"/tasks")}

      {:error, {context, error}} ->
        ErrorLog.log_error("task_live.show.#{context}", error, public_id: public_id)

        {:ok,
         socket
         |> put_flash(:error, "タスクの取得に失敗しました")
         |> push_navigate(to: ~p"/tasks")}
    end
  end

  defp load_task_data(public_id, %{company_id: company_id}) do
    with {:ok, %Task{} = task} <- load_task(public_id, company_id),
         {:ok, events} <- load_priority_events(task.id) do
      {:ok, %{task: task, events: events}}
    else
      {:ok, nil} -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp load_task_data(_public_id, _current_user), do: {:error, :not_found}

  defp load_task(public_id, company_id) do
    Task
    |> filter(public_id == ^public_id and company_id == ^company_id)
    |> Ash.read_one(domain: Tasks)
  end

  defp load_priority_events(task_id) do
    query =
      TaskEvent
      |> filter(task_id == ^task_id and event_type == "priority_changed")
      |> sort(id: :desc)

    case Ash.read(query, domain: Tasks) do
      {:ok, events} ->
        Ash.load(events, [:actor], domain: Tasks)

      {:error, error} ->
        {:error, {:load_priority_events, error}}
    end
  end

  defp assign_task_socket(socket, data, current_user, assignees) do
    priority_form =
      data.task
      |> AshPhoenix.Form.for_update(:set_priority, domain: Tasks)
      |> to_form()

    edit_form =
      data.task
      |> AshPhoenix.Form.for_update(:update, domain: Tasks)
      |> to_form()

    socket
    |> assign(:page_title, "Task #{data.task.public_id}")
    |> assign(:current_user, current_user)
    |> assign(:task, data.task)
    |> assign(:assignees, assignees)
    |> assign(:edit_form, edit_form)
    |> assign(:priority_form, priority_form)
    |> assign(:priority_events, data.events)
  end

  @impl Phoenix.LiveView
  def handle_event("validate_edit", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_form, params)
    {:noreply, assign(socket, :edit_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_edit", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.edit_form, params: params) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "タスクを更新しました")
         |> assign(:task, task)
         |> assign(:edit_form, task |> AshPhoenix.Form.for_update(:update, domain: Tasks) |> to_form())
         |> assign(
           :priority_form,
           task |> AshPhoenix.Form.for_update(:set_priority, domain: Tasks) |> to_form()
         )}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "タスクの更新に失敗しました")
         |> assign(:edit_form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", _params, socket) do
    case Ash.destroy(socket.assigns.task, domain: Tasks) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "タスクを削除しました")
         |> push_navigate(to: ~p"/tasks")}

      {:ok, _task} ->
        {:noreply,
         socket
         |> put_flash(:info, "タスクを削除しました")
         |> push_navigate(to: ~p"/tasks")}

      {:error, error} ->
        ErrorLog.log_error("task_live.show.delete", error, task_id: socket.assigns.task.id)
        {:noreply, put_flash(socket, :error, "タスクの削除に失敗しました")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_priority", %{"form" => params}, socket) do
    params = put_actor_id(params, socket)
    form = AshPhoenix.Form.validate(socket.assigns.priority_form, params)
    {:noreply, assign(socket, :priority_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_priority", %{"form" => params}, socket) do
    params = put_actor_id(params, socket)

    case AshPhoenix.Form.submit(socket.assigns.priority_form, params: params) do
      {:ok, task} ->
        events =
          case load_priority_events(task.id) do
            {:ok, events} -> events
            {:error, error} -> log_and_keep_events(socket, error)
          end

        priority_form =
          task
          |> AshPhoenix.Form.for_update(:set_priority, domain: Tasks)
          |> to_form()

        edit_form =
          task
          |> AshPhoenix.Form.for_update(:update, domain: Tasks)
          |> to_form()

        {:noreply,
         socket
         |> put_flash(:info, "優先度を更新しました")
         |> assign(:task, task)
         |> assign(:edit_form, edit_form)
         |> assign(:priority_form, priority_form)
         |> assign(:priority_events, events)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "優先度の更新に失敗しました")
         |> assign(:priority_form, form)}
    end
  end

  defp put_actor_id(params, %{assigns: %{current_user: %User{id: id}}}) do
    Map.put(params, "actor_id", id)
  end

  defp put_actor_id(params, _socket), do: params

  defp log_and_keep_events(socket, error) do
    ErrorLog.log_error("task_live.show.reload_priority_events", error, task_id: socket.assigns.task.id)
    socket.assigns.priority_events
  end

  defp priority_options do
    [
      {"低", "low"},
      {"中", "medium"},
      {"高", "high"}
    ]
  end

  defp status_options do
    [
      {"未着手", "todo"},
      {"進行中", "in_progress"},
      {"完了", "done"}
    ]
  end

  defp assignee_label(nil, _assignees), do: "-"

  defp assignee_label(assignee_id, assignees) do
    case Enum.find(assignees, &(&1.id == assignee_id)) do
      nil -> "User #{assignee_id}"
      user -> CurrentUser.display_label(user)
    end
  end

  defp actor_label(%TaskEvent{actor: %User{} = user}), do: CurrentUser.display_label(user)
  defp actor_label(%TaskEvent{actor_id: actor_id}), do: "User #{actor_id}"

  defp event_value(%TaskEvent{data: data}, "from") when is_map(data), do: Map.get(data, "from") || Map.get(data, :from)
  defp event_value(%TaskEvent{data: data}, "to") when is_map(data), do: Map.get(data, "to") || Map.get(data, :to)
  defp event_value(_event, _key), do: nil

  defp format_dt(nil), do: "-"

  defp format_dt(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Task {@task.public_id}
        <:subtitle>{@task.title}</:subtitle>
        <:actions>
          <.button
            type="button"
            phx-click="delete"
            data-confirm="このタスクを削除しますか？"
          >
            削除
          </.button>
          <.button navigate={~p"/tasks"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 gap-6">
        <div class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
          <.list>
            <:item title="Public ID">{@task.public_id}</:item>
            <:item title="Status">{@task.status}</:item>
            <:item title="Priority">{@task.priority}</:item>
            <:item title="Assignee">{assignee_label(@task.assignee_id, @assignees)}</:item>
            <:item title="Due date">{@task.due_date || "-"}</:item>
            <:item title="Inserted at">{format_dt(@task.inserted_at)}</:item>
          </.list>

          <div class="mt-4">
            <h3 class="font-semibold">詳細</h3>
            <p class="mt-2 whitespace-pre-wrap text-sm opacity-80">
              {@task.description || "-"}
            </p>
          </div>
        </div>

        <div class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
          <h3 class="font-semibold">タスク編集</h3>
          <.form
            for={@edit_form}
            id="task-edit-form"
            phx-change="validate_edit"
            phx-submit="save_edit"
          >
            <.input field={@edit_form[:title]} label="タイトル" maxlength="200" required />
            <.input field={@edit_form[:description]} type="textarea" label="説明" />

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input
                field={@edit_form[:status]}
                type="select"
                label="ステータス"
                options={status_options()}
              />
              <.input field={@edit_form[:due_date]} type="date" label="期限" />
            </div>

            <.input
              field={@edit_form[:assignee_id]}
              type="select"
              label="担当者"
              prompt="未割り当て"
              options={FormOptions.user_options(@assignees)}
            />

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary">保存</.button>
            </div>
          </.form>
        </div>

        <div class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
          <h3 class="font-semibold">優先度変更</h3>
          <.form
            for={@priority_form}
            id="task-priority-form"
            phx-change="validate_priority"
            phx-submit="save_priority"
          >
            <.input
              field={@priority_form[:priority]}
              type="select"
              label="Priority"
              options={priority_options()}
            />

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary">更新</.button>
            </div>
          </.form>
        </div>

        <div class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
          <h3 class="font-semibold">優先度変更履歴</h3>

          <div id="task-priority-events" class="mt-4 space-y-3">
            <div :if={@priority_events == []} id="task-priority-events-empty" class="text-sm opacity-70">
              まだ優先度変更履歴がありません。
            </div>

            <div
              :for={event <- @priority_events}
              id={"task-priority-event-#{event.id}"}
              class="rounded-xl border border-base-200 p-4 text-sm"
            >
              <div class="flex items-center justify-between text-xs text-base-content/60">
                <span>{actor_label(event)}</span>
                <span>{format_dt(event.inserted_at)}</span>
              </div>
              <div class="mt-2 font-medium">
                {event_value(event, "from") || "-"} → {event_value(event, "to") || "-"}
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
