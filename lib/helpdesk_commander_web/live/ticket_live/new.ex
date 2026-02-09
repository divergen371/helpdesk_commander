defmodule HelpdeskCommanderWeb.TicketLive.New do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    users =
      if external_user? and current_user do
        [current_user]
      else
        User
        |> Ash.read!(domain: Accounts)
        |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      end

    form =
      Ticket
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "New Ticket")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:users, users)
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    params = maybe_put_requester_id(params, socket)
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    params = maybe_put_requester_id(params, socket)

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
      {user_label(user), user.id}
    end)
  end

  defp user_label(%User{role: "system"}), do: "System"
  defp user_label(%User{name: name, email: email}), do: "#{name} <#{email}>"

  defp maybe_put_requester_id(params, %{assigns: %{current_user_external?: true, current_user: %User{id: id}}}) do
    Map.put(params, "requester_id", id)
  end

  defp maybe_put_requester_id(params, _socket), do: params

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

            <%= if @current_user_external? do %>
              <div class="rounded-box border border-base-200 p-4 text-sm">
                <p class="text-xs uppercase tracking-wide opacity-60">依頼者</p>
                <p class="mt-1 font-medium">{user_label(@current_user)}</p>
              </div>
              <.input
                field={@form[:requester_id]}
                type="hidden"
                value={@current_user.id}
              />
            <% else %>
              <.input
                field={@form[:requester_id]}
                type="select"
                label="依頼者"
                prompt="選択してください"
                options={user_options(@users)}
                required
              />
            <% end %>

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
