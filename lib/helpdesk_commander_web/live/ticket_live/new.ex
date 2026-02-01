defmodule HelpdeskCommanderWeb.TicketLive.New do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    users =
      User
      |> Ash.read!(domain: Accounts)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    form =
      Ticket
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "New Ticket")
     |> assign(:users, users)
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> put_flash(:info, "チケットを作成しました")
         |> push_navigate(to: ~p"/tickets/#{ticket.public_id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "入力内容を確認してください")
         |> assign(:form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("create_sample_user", _params, socket) do
    email = "user+#{System.unique_integer([:positive])}@example.com"

    changeset = Ash.Changeset.for_create(User, :create, %{email: email, name: "Sample User"})

    _user = Ash.create!(changeset, domain: Accounts)

    users =
      User
      |> Ash.read!(domain: Accounts)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    {:noreply,
     socket
     |> put_flash(:info, "サンプルユーザーを作成しました")
     |> assign(:users, users)}
  end

  defp user_options(users) do
    Enum.map(users, fn user ->
      {"#{user.name} <#{user.email}>", user.id}
    end)
  end

  defp status_options do
    [
      {"new", "new"},
      {"open", "open"},
      {"pending", "pending"},
      {"resolved", "resolved"},
      {"closed", "closed"}
    ]
  end

  defp priority_options do
    [
      {"p1", "p1"},
      {"p2", "p2"},
      {"p3", "p3"},
      {"p4", "p4"}
    ]
  end

  defp type_options do
    [
      {"question", "question"},
      {"incident", "incident"},
      {"request", "request"}
    ]
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        新規チケット
        <:subtitle>まずは最小の項目で作成</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div :if={@users == []} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <p class="font-semibold">ユーザーがまだありません</p>
          <p class="text-sm opacity-80">requester が必須なので、まずサンプルユーザーを作成してください。</p>
        </div>
        <div class="flex-1" />
        <.button type="button" phx-click="create_sample_user">
          サンプルユーザー作成
        </.button>
      </div>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@form} id="ticket-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:subject]} label="件名" />
            <.input field={@form[:description]} type="textarea" label="詳細" />

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <.input field={@form[:type]} type="select" label="種別" options={type_options()} />
              <.input field={@form[:status]} type="select" label="ステータス" options={status_options()} />
              <.input field={@form[:priority]} type="select" label="優先度" options={priority_options()} />
            </div>

            <.input
              field={@form[:requester_id]}
              type="select"
              label="依頼者"
              prompt="選択してください"
              options={user_options(@users)}
              required
            />

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary" disabled={@users == []}>
                作成
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
