defmodule HelpdeskCommanderWeb.TicketLive.Show do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketMessage

  @impl Phoenix.LiveView
  def mount(%{"public_id" => public_id}, _session, socket) do
    ticket = Ash.get!(Ticket, %{public_id: public_id}, domain: Helpdesk)

    users =
      User
      |> Ash.read!(domain: Accounts)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    users_by_id = Map.new(users, &{&1.id, &1})

    messages =
      TicketMessage
      |> filter(ticket_id == ^ticket.id)
      |> Ash.read!(domain: Helpdesk)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    update_form =
      ticket
      |> AshPhoenix.Form.for_update(:update, domain: Helpdesk)
      |> to_form()

    message_form =
      TicketMessage
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form()

    {:ok,
     socket
     |> assign(:page_title, "Ticket #{ticket.public_id}")
     |> assign(:ticket, ticket)
     |> assign(:users, users)
     |> assign(:users_by_id, users_by_id)
     |> assign(:update_form, update_form)
     |> assign(:message_form, message_form)
     |> stream(:messages, messages)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate_update", %{"form" => params}, socket) do
    update_form = AshPhoenix.Form.validate(socket.assigns.update_form, params)
    {:noreply, assign(socket, :update_form, update_form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_update", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.update_form, params: params) do
      {:ok, ticket} ->
        update_form =
          ticket
          |> AshPhoenix.Form.for_update(:update, domain: Helpdesk)
          |> to_form()

        {:noreply,
         socket
         |> put_flash(:info, "更新しました")
         |> assign(:ticket, ticket)
         |> assign(:update_form, update_form)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "更新に失敗しました")
         |> assign(:update_form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_message", %{"form" => params}, socket) do
    message_form = AshPhoenix.Form.validate(socket.assigns.message_form, params)
    {:noreply, assign(socket, :message_form, message_form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_message", %{"form" => params}, socket) do
    params =
      params
      |> Map.put("ticket_id", socket.assigns.ticket.id)
      |> Map.put_new("sender_id", socket.assigns.ticket.requester_id)

    case AshPhoenix.Form.submit(socket.assigns.message_form, params: params) do
      {:ok, message} ->
        ticket =
          socket.assigns.ticket
          |> Ash.Changeset.for_update(:update, %{latest_message_at: DateTime.utc_now()})
          |> Ash.update!(domain: Helpdesk)

        message_form =
          TicketMessage
          |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
          |> to_form()

        {:noreply,
         socket
         |> put_flash(:info, "メッセージを追加しました")
         |> assign(:ticket, ticket)
         |> assign(:message_form, message_form)
         |> stream_insert(:messages, message)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "メッセージの追加に失敗しました")
         |> assign(:message_form, form)}
    end
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

  defp sender_label(users_by_id, sender_id) do
    case Map.get(users_by_id, sender_id) do
      %User{} = user -> user_label(user)
      _user -> "User #{sender_id}"
    end
  end

  defp user_options(users) do
    Enum.map(users, fn user ->
      {user_label(user), user.id}
    end)
  end

  defp user_label(%User{role: "system"}), do: "System"
  defp user_label(%User{name: name, email: email}), do: "#{name} <#{email}>"

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Ticket {@ticket.public_id}
        <:subtitle>{@ticket.subject}</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 gap-6">
        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <.list>
              <:item title="Public ID">{@ticket.public_id}</:item>
              <:item title="Status">{@ticket.status}</:item>
              <:item title="Priority">{@ticket.priority}</:item>
              <:item title="Type">{@ticket.type}</:item>
              <:item title="Inserted at">{format_dt(@ticket.inserted_at)}</:item>
            </.list>

            <div class="mt-4">
              <h3 class="font-semibold">詳細</h3>
              <p class="mt-2 whitespace-pre-wrap text-sm opacity-80">{@ticket.description}</p>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">ステータス更新</h3>
            <.form
              for={@update_form}
              id="ticket-status-form"
              phx-change="validate_update"
              phx-submit="save_update"
            >
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@update_form[:status]}
                  type="select"
                  label="Status"
                  options={status_options()}
                />
                <.input
                  field={@update_form[:priority]}
                  type="select"
                  label="Priority"
                  options={[{"p1", "p1"}, {"p2", "p2"}, {"p3", "p3"}, {"p4", "p4"}]}
                />
              </div>

              <div class="mt-6 flex justify-end">
                <.button type="submit" variant="primary">更新</.button>
              </div>
            </.form>
          </div>
        </div>

        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">会話ログ</h3>

            <div id="ticket-messages" phx-update="stream" class="mt-4 space-y-4">
              <div id="ticket-messages-empty" class="hidden only:block text-sm opacity-70">
                まだメッセージがありません。
              </div>

              <div
                :for={{id, message} <- @streams.messages}
                id={id}
                class="rounded-box border border-base-200 p-4"
              >
                <div class="flex items-center justify-between text-xs text-base-content/60">
                  <span>{sender_label(@users_by_id, message.sender_id)}</span>
                  <span>{format_dt(message.inserted_at)}</span>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm">{message.body}</p>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">コメント追加</h3>

            <.form
              for={@message_form}
              id="ticket-message-form"
              phx-change="validate_message"
              phx-submit="save_message"
            >
              <.input field={@message_form[:body]} type="textarea" label="本文" />
              <.input
                field={@message_form[:sender_id]}
                type="select"
                label="投稿者"
                prompt="選択してください"
                options={user_options(@users)}
                required
              />
              <.input field={@message_form[:ticket_id]} type="hidden" value={@ticket.id} />

              <div class="mt-6 flex justify-end">
                <.button type="submit" variant="primary">投稿</.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp format_dt(nil), do: "-"

  defp format_dt(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
