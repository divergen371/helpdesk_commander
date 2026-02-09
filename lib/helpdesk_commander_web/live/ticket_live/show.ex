defmodule HelpdeskCommanderWeb.TicketLive.Show do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommanderWeb.CurrentUser

  @messages_page_size 20
  @events_page_size 20

  @impl Phoenix.LiveView
  def mount(%{"public_id" => public_id}, session, socket) do
    ticket = Ash.get!(Ticket, %{public_id: public_id}, domain: Helpdesk)
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    can_view? =
      not external_user? or
        (current_user &&
           (ticket.requester_id == current_user.id || ticket.visibility_scope == "global"))

    if can_view? do
      can_post_public? =
        not external_user? or (current_user && ticket.requester_id == current_user.id)

      users =
        User
        |> Ash.read!(domain: Accounts)
        |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

      users_by_id = Map.new(users, &{&1.id, &1})

      {public_conversation, private_conversation} = ensure_conversations(ticket)

      {public_messages, public_has_more?, public_oldest_id} =
        fetch_messages(public_conversation.id)

      {private_messages, private_has_more?, private_oldest_id} =
        if external_user? do
          {[], false, nil}
        else
          fetch_messages(private_conversation.id)
        end

      {events, events_has_more?, events_oldest_id} =
        if external_user? do
          {[], false, nil}
        else
          fetch_events(ticket.id)
        end

      update_form =
        ticket
        |> AshPhoenix.Form.for_update(:update, domain: Helpdesk)
        |> to_form()

      public_message_form =
        ConversationMessage
        |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
        |> to_form(as: "public_message")

      private_message_form =
        ConversationMessage
        |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
        |> to_form(as: "private_message")

      {:ok,
       socket
       |> assign(:page_title, "Ticket #{ticket.public_id}")
       |> assign(:ticket, ticket)
       |> assign(:users, users)
       |> assign(:users_by_id, users_by_id)
       |> assign(:current_user, current_user)
       |> assign(:current_user_external?, external_user?)
       |> assign(:can_post_public?, can_post_public?)
       |> assign(:update_form, update_form)
       |> assign(:public_message_form, public_message_form)
       |> assign(:private_message_form, private_message_form)
       |> assign(:public_conversation, public_conversation)
       |> assign(:private_conversation, private_conversation)
       |> assign(:public_messages_has_more?, public_has_more?)
       |> assign(:public_messages_oldest_id, public_oldest_id)
       |> assign(:private_messages_has_more?, private_has_more?)
       |> assign(:private_messages_oldest_id, private_oldest_id)
       |> assign(:events_has_more?, events_has_more?)
       |> assign(:events_oldest_id, events_oldest_id)
       |> stream(:public_messages, public_messages)
       |> stream(:private_messages, private_messages)
       |> stream(:events, events)}
    else
      {:ok,
       socket
       |> put_flash(:error, "アクセス権限がありません")
       |> push_navigate(to: ~p"/tickets")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_older_messages", %{"kind" => kind}, socket) do
    if forbidden_read?(socket, kind) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      before_id = message_oldest_id(socket, kind)
      conversation_id = conversation_id_for_kind(socket, kind)

      {messages, has_more?, oldest_id} = fetch_messages(conversation_id, before_id)
      next_oldest_id = oldest_id || before_id

      {:noreply,
       socket
       |> assign(message_has_more_key(kind), has_more?)
       |> assign(message_oldest_key(kind), next_oldest_id)
       |> stream(message_stream_name(kind), messages, at: -1)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_older_events", _params, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      before_id = socket.assigns.events_oldest_id
      {events, has_more?, oldest_id} = fetch_events(socket.assigns.ticket.id, before_id)

      {:noreply,
       socket
       |> assign(:events_has_more?, has_more?)
       |> assign(:events_oldest_id, oldest_id || before_id)
       |> stream(:events, events, at: -1)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_update", %{"form" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      update_form = AshPhoenix.Form.validate(socket.assigns.update_form, params)
      {:noreply, assign(socket, :update_form, update_form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save_update", %{"form" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
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
  end

  @impl Phoenix.LiveView
  def handle_event("validate_message", %{"kind" => kind} = params, socket) do
    if forbidden_post?(socket, kind) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      form_params = Map.get(params, message_form_key(kind), %{})
      conversation_id = conversation_id_for_kind(socket, kind)

      message_params =
        form_params
        |> Map.put("conversation_id", conversation_id)
        |> put_sender_id(socket)

      form =
        socket
        |> message_form_for_kind(kind)
        |> AshPhoenix.Form.validate(message_params)

      {:noreply, assign(socket, message_form_assign_key(kind), form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save_message", %{"kind" => kind} = params, socket) do
    if forbidden_post?(socket, kind) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      form_params = Map.get(params, message_form_key(kind), %{})
      conversation_id = conversation_id_for_kind(socket, kind)

      message_params =
        form_params
        |> Map.put("conversation_id", conversation_id)
        |> put_sender_id(socket)

      submission =
        socket
        |> message_form_for_kind(kind)
        |> AshPhoenix.Form.submit(params: message_params)

      case submission do
        {:ok, message} ->
          ticket = Ash.get!(Ticket, %{id: socket.assigns.ticket.id}, domain: Helpdesk)

          form =
            ConversationMessage
            |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
            |> to_form(as: message_form_key(kind))

          {:noreply,
           socket
           |> put_flash(:info, "メッセージを追加しました")
           |> assign(:ticket, ticket)
           |> assign(message_form_assign_key(kind), form)
           |> stream_insert(message_stream_name(kind), message)}

        {:error, form} ->
          {:noreply,
           socket
           |> put_flash(:error, "メッセージの追加に失敗しました")
           |> assign(message_form_assign_key(kind), form)}
      end
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
  defp user_label(%User{display_name: name, email: email}), do: "#{name} <#{email}>"

  defp ensure_conversations(%Ticket{} = ticket) do
    {
      get_or_create_conversation(ticket, "internal_public"),
      get_or_create_conversation(ticket, "internal_private")
    }
  end

  defp get_or_create_conversation(%Ticket{} = ticket, kind) do
    conversation_result =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == ^kind)
      |> Ash.read_one(domain: Helpdesk)

    case conversation_result do
      {:ok, %Conversation{} = conversation} ->
        conversation

      _result ->
        Conversation
        |> Ash.Changeset.for_create(:create, %{
          ticket_id: ticket.id,
          kind: kind,
          created_by_id: ticket.requester_id
        })
        |> Ash.create!(domain: Helpdesk)
    end
  end

  defp fetch_messages(conversation_id, before_id \\ nil) do
    limit = @messages_page_size

    query =
      ConversationMessage
      |> filter(conversation_id == ^conversation_id)
      |> sort(id: :desc)
      |> maybe_before_id(before_id)

    raw_messages =
      query
      |> Ash.Query.limit(limit + 1)
      |> Ash.read!(domain: Helpdesk)

    {messages, has_more?} = trim_to_limit(raw_messages, limit)
    ordered_messages = Enum.reverse(messages)
    oldest_id = oldest_id_from_list(ordered_messages)

    {ordered_messages, has_more?, oldest_id}
  end

  defp fetch_events(ticket_id, before_id \\ nil) do
    limit = @events_page_size

    query =
      TicketEvent
      |> filter(ticket_id == ^ticket_id)
      |> sort(id: :desc)
      |> maybe_before_id(before_id)

    raw_events =
      query
      |> Ash.Query.limit(limit + 1)
      |> Ash.read!(domain: Helpdesk)

    {events, has_more?} = trim_to_limit(raw_events, limit)
    ordered_events = Enum.reverse(events)
    oldest_id = oldest_id_from_list(ordered_events)

    {ordered_events, has_more?, oldest_id}
  end

  defp message_form_key("public"), do: "public_message"
  defp message_form_key("private"), do: "private_message"

  defp message_form_assign_key("public"), do: :public_message_form
  defp message_form_assign_key("private"), do: :private_message_form

  defp message_form_for_kind(socket, "public"), do: socket.assigns.public_message_form
  defp message_form_for_kind(socket, "private"), do: socket.assigns.private_message_form

  defp message_stream_name("public"), do: :public_messages
  defp message_stream_name("private"), do: :private_messages

  defp message_oldest_key("public"), do: :public_messages_oldest_id
  defp message_oldest_key("private"), do: :private_messages_oldest_id

  defp message_oldest_id(socket, kind), do: Map.get(socket.assigns, message_oldest_key(kind))

  defp message_has_more_key("public"), do: :public_messages_has_more?
  defp message_has_more_key("private"), do: :private_messages_has_more?

  defp conversation_id_for_kind(socket, "public"), do: socket.assigns.public_conversation.id
  defp conversation_id_for_kind(socket, "private"), do: socket.assigns.private_conversation.id

  defp forbidden_read?(socket, "private"), do: socket.assigns.current_user_external?
  defp forbidden_read?(_socket, _kind), do: false

  defp forbidden_post?(socket, "private"), do: socket.assigns.current_user_external?

  defp forbidden_post?(socket, "public") do
    socket.assigns.current_user_external? and not socket.assigns.can_post_public?
  end

  defp forbidden_post?(_socket, _kind), do: false

  defp put_sender_id(params, %{assigns: %{current_user_external?: true, current_user: %User{id: id}}}) do
    Map.put(params, "sender_id", id)
  end

  defp put_sender_id(params, socket) do
    Map.put_new(params, "sender_id", socket.assigns.ticket.requester_id)
  end

  defp event_label(%TicketEvent{event_type: "ticket_created"}), do: "チケット作成"

  defp event_label(%TicketEvent{event_type: "message_posted", data: data}) do
    case event_conversation_kind(data) do
      "internal_private" -> "内部メモ投稿"
      "internal_public" -> "公開メッセージ投稿"
      _kind -> "メッセージ投稿"
    end
  end

  defp event_label(%TicketEvent{event_type: event_type}), do: event_type

  defp event_data_label(%TicketEvent{data: data, event_type: event_type}) do
    cond do
      event_type == "message_posted" -> nil
      data in [nil, %{}] -> nil
      true -> inspect(data)
    end
  end

  defp event_conversation_kind(data) when is_map(data) do
    Map.get(data, "conversation_kind") || Map.get(data, :conversation_kind)
  end

  defp oldest_id_from_list([]), do: nil
  defp oldest_id_from_list([first | _rest]), do: first.id

  defp maybe_before_id(query, nil), do: query
  defp maybe_before_id(query, before_id), do: filter(query, id < ^before_id)

  defp trim_to_limit(items, limit) do
    if length(items) > limit do
      {Enum.take(items, limit), true}
    else
      {items, false}
    end
  end

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

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
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
            <div class="flex items-center justify-between">
              <h3 class="font-semibold">公開会話ログ</h3>
              <.button
                :if={@public_messages_has_more?}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="load_older_messages"
                phx-value-kind="public"
              >
                もっと読む
              </.button>
            </div>

            <div id="ticket-messages-public" phx-update="stream" class="mt-4 space-y-4">
              <div id="ticket-messages-public-empty" class="hidden only:block text-sm opacity-70">
                まだメッセージがありません。
              </div>

              <div
                :for={{id, message} <- @streams.public_messages}
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

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h3 class="font-semibold">内部メモ</h3>
              <.button
                :if={@private_messages_has_more?}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="load_older_messages"
                phx-value-kind="private"
              >
                もっと読む
              </.button>
            </div>

            <div id="ticket-messages-private" phx-update="stream" class="mt-4 space-y-4">
              <div id="ticket-messages-private-empty" class="hidden only:block text-sm opacity-70">
                まだメモがありません。
              </div>

              <div
                :for={{id, message} <- @streams.private_messages}
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
        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h3 class="font-semibold">イベントログ</h3>
              <.button
                :if={@events_has_more?}
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="load_older_events"
              >
                もっと読む
              </.button>
            </div>

            <div id="ticket-events" phx-update="stream" class="mt-4 space-y-3">
              <div id="ticket-events-empty" class="hidden only:block text-sm opacity-70">
                まだイベントがありません。
              </div>

              <div
                :for={{id, event} <- @streams.events}
                id={id}
                class="rounded-box border border-base-200 p-3 text-sm"
              >
                <div class="flex items-center justify-between text-xs text-base-content/60">
                  <span>{sender_label(@users_by_id, event.actor_id)}</span>
                  <span>{format_dt(event.inserted_at)}</span>
                </div>
                <div class="mt-2 font-medium">{event_label(event)}</div>
                <div :if={event_data_label(event)} class="mt-1 text-xs opacity-70">
                  {event_data_label(event)}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-100 border border-base-200">
          <div class="card-body space-y-8">
            <div>
              <h3 class="font-semibold">公開コメント追加</h3>

              <.form
                :if={@can_post_public?}
                for={@public_message_form}
                id="ticket-message-form-public"
                phx-change="validate_message"
                phx-submit="save_message"
                phx-value-kind="public"
              >
                <.input
                  id="public_message_body"
                  name="public_message[body]"
                  field={@public_message_form[:body]}
                  type="textarea"
                  label="本文"
                />
                <%= if @current_user_external? do %>
                  <.input
                    id="public_message_sender_id"
                    name="public_message[sender_id]"
                    field={@public_message_form[:sender_id]}
                    type="hidden"
                    value={@current_user.id}
                  />
                  <div class="mt-3 text-xs uppercase tracking-wide opacity-60">投稿者</div>
                  <div class="mt-1 text-sm font-medium">{user_label(@current_user)}</div>
                <% else %>
                  <.input
                    id="public_message_sender_id"
                    name="public_message[sender_id]"
                    field={@public_message_form[:sender_id]}
                    type="select"
                    label="投稿者"
                    prompt="選択してください"
                    options={user_options(@users)}
                    required
                  />
                <% end %>

                <div class="mt-6 flex justify-end">
                  <.button type="submit" variant="primary">投稿</.button>
                </div>
              </.form>
              <div :if={!@can_post_public?} class="mt-3 text-sm opacity-70">
                このチケットへの投稿はできません。
              </div>
            </div>

            <div :if={!@current_user_external?}>
              <h3 class="font-semibold">内部メモ追加</h3>

              <.form
                for={@private_message_form}
                id="ticket-message-form-private"
                phx-change="validate_message"
                phx-submit="save_message"
                phx-value-kind="private"
              >
                <.input
                  id="private_message_body"
                  name="private_message[body]"
                  field={@private_message_form[:body]}
                  type="textarea"
                  label="本文"
                />
                <.input
                  id="private_message_sender_id"
                  name="private_message[sender_id]"
                  field={@private_message_form[:sender_id]}
                  type="select"
                  label="投稿者"
                  prompt="選択してください"
                  options={user_options(@users)}
                  required
                />

                <div class="mt-6 flex justify-end">
                  <.button type="submit" variant="primary">投稿</.button>
                </div>
              </.form>
            </div>
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
