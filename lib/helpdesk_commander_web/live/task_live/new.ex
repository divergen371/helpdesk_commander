defmodule HelpdeskCommanderWeb.TaskLive.New do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommanderWeb.FormOptions

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    {assignees, socket} =
      case FormOptions.load_internal_users(current_user) do
        {:ok, assignees} ->
          {assignees, socket}

        {:error, error} ->
          ErrorLog.log_error("task_live.new.load_assignees", error)

          {[], put_flash(socket, :error, "担当者一覧の取得に失敗しました")}
      end

    form =
      Task
      |> AshPhoenix.Form.for_create(:create, domain: Tasks)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "New Task")
     |> assign(:assignees, assignees)
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, put_company_id(params, socket))

    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: put_company_id(params, socket)) do
      {:ok, task} ->
        {:noreply,
         socket
         |> put_flash(:info, "タスクを作成しました")
         |> push_navigate(to: ~p"/tasks/#{task.public_id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "入力内容を確認してください")
         |> assign(:form, form)}
    end
  end

  defp put_company_id(params, %{assigns: %{current_user: current_user}}) do
    Map.put(params, "company_id", current_user.company_id)
  end

  defp status_options do
    [{"未着手", "todo"}, {"進行中", "in_progress"}, {"完了", "done"}]
  end

  defp priority_options do
    [{"低", "low"}, {"中", "medium"}, {"高", "high"}]
  end

  defp assignee_options(assignees) do
    FormOptions.user_options(assignees)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        新規タスク
        <:subtitle>タスクの作成</:subtitle>
        <:actions>
          <.button navigate={~p"/tasks"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div class="rounded-2xl border border-base-200 bg-base-100 p-6 shadow-sm">
        <.form for={@form} id="task-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} label="タイトル" maxlength="200" required />
          <.input field={@form[:description]} type="textarea" label="説明" />

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:status]}
              type="select"
              label="ステータス"
              options={status_options()}
            />
            <.input
              field={@form[:priority]}
              type="select"
              label="優先度"
              options={priority_options()}
            />
          </div>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:due_date]} type="date" label="期限" />
            <.input
              field={@form[:assignee_id]}
              type="select"
              label="担当者"
              prompt="未割り当て"
              options={assignee_options(@assignees)}
            />
          </div>

          <div class="mt-6 flex justify-end">
            <.button type="submit" variant="primary">作成</.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
