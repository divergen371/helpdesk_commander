# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
defmodule HelpdeskCommanderWeb.TicketLive.Show do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Incident
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Helpdesk.TicketRelations
  alias HelpdeskCommander.Helpdesk.TicketVerification
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.TicketTaskLink
  alias HelpdeskCommanderWeb.CurrentUser

  @messages_page_size 20
  @events_page_size 20

  @impl Phoenix.LiveView
  def mount(%{"public_id" => public_id}, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    case load_ticket_data(public_id, current_user, external_user?) do
      {:ok, data} ->
        {:ok, assign_ticket_socket(socket, data)}

      {:error, :forbidden} ->
        {:ok,
         socket
         |> put_flash(:error, "アクセス権限がありません")
         |> push_navigate(to: ~p"/tickets")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "チケットが見つかりません")
         |> push_navigate(to: ~p"/tickets")}

      {:error, {context, error}} ->
        ErrorLog.log_error("ticket_live.show.#{context}", error, public_id: public_id)

        {:ok,
         socket
         |> put_flash(:error, error_message(context))
         |> push_navigate(to: ~p"/tickets")}
    end
  end

  defp ticket_status_form(%Ticket{} = ticket, current_user) do
    AshPhoenix.Form.for_update(ticket, :set_status, form_options(current_user))
  end

  defp ticket_update_form(%Ticket{} = ticket, current_user) do
    AshPhoenix.Form.for_update(ticket, :update, form_options(current_user))
  end

  defp form_options(current_user) do
    Keyword.merge([domain: Helpdesk, warn_on_unhandled_errors?: false], actor_option(current_user))
  end

  defp actor_option(%User{} = user), do: [actor: user]
  defp actor_option(_current_user), do: []

  defp actor_action_opts(%{assigns: %{current_user: %User{} = user}}), do: [actor: user]
  defp actor_action_opts(_socket), do: []

  defp load_ticket_data(public_id, current_user, external_user?) do
    with {:ok, ticket} <- load_ticket(public_id),
         :ok <- authorize_ticket(ticket, current_user, external_user?),
         {:ok, users, users_by_id} <- load_users(ticket.company_id),
         {:ok, conversations} <- ensure_conversations(ticket),
         {:ok, task_links, linkable_tasks} <- load_task_links(ticket, current_user),
         {:ok, ticket_links, linkable_tickets} <- load_ticket_relations(ticket, current_user) do
      build_ticket_data(
        ticket,
        current_user,
        external_user?,
        users,
        users_by_id,
        conversations,
        %{
          task_links: task_links,
          linkable_tasks: linkable_tasks,
          ticket_links: ticket_links,
          linkable_tickets: linkable_tickets
        }
      )
    else
      {:error, _reason} = error -> error
    end
  end

  defp load_ticket(public_id) do
    case Helpdesk.get_ticket_by_public_id(public_id) do
      {:ok, %Ticket{} = ticket} ->
        with {:ok, ticket} <- Helpdesk.load_ticket_product(ticket),
             {:ok, ticket} <- Helpdesk.load_ticket_stats(ticket) do
          {:ok, ticket}
        else
          {:error, error} -> {:error, {:load_ticket, error}}
        end

      {:ok, nil} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, {:load_ticket, error}}
    end
  end

  defp authorize_ticket(ticket, %User{} = current_user, external_user?) do
    cond do
      ticket.visibility_scope == "global" ->
        :ok

      external_user? ->
        if Authorization.same_company?(current_user, ticket.company_id) and
             ticket.requester_id == current_user.id do
          :ok
        else
          {:error, :forbidden}
        end

      Authorization.same_company?(current_user, ticket.company_id) ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp authorize_ticket(_ticket, _current_user, _external_user?), do: {:error, :forbidden}

  defp build_ticket_data(
         ticket,
         current_user,
         external_user?,
         users,
         users_by_id,
         {public_conversation, private_conversation},
         relations
       ) do
    can_post_public? =
      not external_user? or (current_user && ticket.requester_id == current_user.id)

    can_approve? = CurrentUser.admin?(current_user)
    assignable_users = selectable_users(users)

    {public_messages, public_has_more?, public_oldest_id, public_warnings} =
      load_messages(public_conversation.id, ticket.id, :public, current_user)

    {private_messages, private_has_more?, private_oldest_id, private_warnings} =
      load_private_messages(external_user?, private_conversation.id, ticket.id, current_user)

    {events, events_has_more?, events_oldest_id, event_warnings} =
      load_events(external_user?, ticket.id)

    {verifications, verification_warnings} = load_verifications(ticket.id)
    {incident, incident_events} = load_incident(ticket, external_user?)

    warnings = public_warnings ++ private_warnings ++ event_warnings ++ verification_warnings

    update_form =
      ticket
      |> ticket_update_form(current_user)
      |> to_form()

    status_form =
      ticket
      |> ticket_status_form(current_user)
      |> to_form()

    public_message_form =
      ConversationMessage
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form(as: "public_message")

    private_message_form =
      ConversationMessage
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form(as: "private_message")

    verification_form =
      TicketVerification
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form(as: "verification")

    {:ok,
     %{
       ticket: ticket,
       users: users,
       assignable_users: assignable_users,
       users_by_id: users_by_id,
       current_user: current_user,
       external_user?: external_user?,
       can_approve?: can_approve?,
       can_post_public?: can_post_public?,
       status_form: status_form,
       update_form: update_form,
       public_message_form: public_message_form,
       private_message_form: private_message_form,
       verification_form: verification_form,
       public_conversation: public_conversation,
       private_conversation: private_conversation,
       public_messages: public_messages,
       public_messages_has_more?: public_has_more?,
       public_messages_oldest_id: public_oldest_id,
       private_messages: private_messages,
       private_messages_has_more?: private_has_more?,
       private_messages_oldest_id: private_oldest_id,
       events: events,
       events_has_more?: events_has_more?,
       events_oldest_id: events_oldest_id,
       verifications: verifications,
       incident: incident,
       incident_events: incident_events,
       incident_form: incident_form(incident),
       incident_event_form: to_form(%{"phase" => "investigation", "body" => ""}, as: "incident_event"),
       task_links: relations.task_links,
       linkable_tasks: relations.linkable_tasks,
       task_link_form: to_form(%{"task_id" => ""}, as: "link"),
       ticket_links: relations.ticket_links,
       linkable_tickets: relations.linkable_tickets,
       ticket_link_form: to_form(%{"related_ticket_id" => "", "relation_type" => "related"}, as: "link"),
       warnings: warnings
     }}
  end

  defp assign_ticket_socket(socket, data) do
    socket
    |> assign(:page_title, "Ticket #{data.ticket.public_id}")
    |> assign(:ticket, data.ticket)
    |> assign(:users, data.users)
    |> assign(:assignable_users, data.assignable_users)
    |> assign(:users_by_id, data.users_by_id)
    |> assign(:current_user, data.current_user)
    |> assign(:current_user_external?, data.external_user?)
    |> assign(:can_approve?, data.can_approve?)
    |> assign(:can_post_public?, data.can_post_public?)
    |> assign(:status_form, data.status_form)
    |> assign(:update_form, data.update_form)
    |> assign(:public_message_form, data.public_message_form)
    |> assign(:private_message_form, data.private_message_form)
    |> assign(:verification_form, data.verification_form)
    |> assign(:verifications, data.verifications)
    |> assign(:incident, data.incident)
    |> assign(:incident_events, data.incident_events)
    |> assign(:incident_form, data.incident_form)
    |> assign(:incident_event_form, data.incident_event_form)
    |> assign(:editing_message_id, nil)
    |> assign(:edit_message_form, nil)
    |> assign(:public_conversation, data.public_conversation)
    |> assign(:private_conversation, data.private_conversation)
    |> assign(:public_messages_has_more?, data.public_messages_has_more?)
    |> assign(:public_messages_oldest_id, data.public_messages_oldest_id)
    |> assign(:private_messages_has_more?, data.private_messages_has_more?)
    |> assign(:private_messages_oldest_id, data.private_messages_oldest_id)
    |> assign(:events_has_more?, data.events_has_more?)
    |> assign(:events_oldest_id, data.events_oldest_id)
    |> assign(:task_links, data.task_links)
    |> assign(:linkable_tasks, data.linkable_tasks)
    |> assign(:task_link_form, data.task_link_form)
    |> assign(:ticket_links, data.ticket_links)
    |> assign(:linkable_tickets, data.linkable_tickets)
    |> assign(:ticket_link_form, data.ticket_link_form)
    |> stream(:public_messages, data.public_messages)
    |> stream(:private_messages, data.private_messages)
    |> stream(:events, data.events)
    |> apply_flash_warnings(data.warnings)
  end

  defp apply_flash_warnings(socket, warnings) do
    Enum.reduce(warnings, socket, fn message, socket ->
      put_flash(socket, :error, message)
    end)
  end

  defp load_messages(conversation_id, ticket_id, kind, current_user) do
    case fetch_messages(conversation_id, nil, current_user) do
      {:ok, {messages, has_more?, oldest_id}} ->
        {messages, has_more?, oldest_id, []}

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.fetch_#{kind}_messages", error,
          ticket_id: ticket_id,
          conversation_id: conversation_id
        )

        {[], false, nil, ["メッセージの取得に失敗しました"]}
    end
  end

  defp load_private_messages(true, _conversation_id, _ticket_id, _current_user),
    do: {[], false, nil, []}

  defp load_private_messages(false, conversation_id, ticket_id, current_user) do
    load_messages(conversation_id, ticket_id, :private, current_user)
  end

  defp load_events(true, _ticket_id), do: {[], false, nil, []}

  defp load_events(false, ticket_id) do
    case fetch_events(ticket_id) do
      {:ok, {events, has_more?, oldest_id}} ->
        {events, has_more?, oldest_id, []}

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.fetch_events", error, ticket_id: ticket_id)
        {[], false, nil, ["イベントの取得に失敗しました"]}
    end
  end

  defp load_incident(_ticket, true), do: {nil, []}

  defp load_incident(ticket, false) do
    case Helpdesk.get_incident(ticket.id, tenant: ticket.company_id) do
      {:ok, %Incident{} = incident} ->
        case Helpdesk.list_incident_events(incident.id, tenant: ticket.company_id) do
          {:ok, events} ->
            {incident, events}

          {:error, error} ->
            ErrorLog.log_error("ticket_live.show.load_incident_events", error, ticket_id: ticket.id)
            {incident, []}
        end

      {:ok, nil} ->
        {nil, []}

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.load_incident", error, ticket_id: ticket.id)
        {nil, []}
    end
  end

  defp incident_form(nil) do
    to_form(%{"severity" => "sev3", "impact_scope" => "", "announcement" => ""}, as: "incident")
  end

  defp incident_form(incident) do
    to_form(
      %{
        "severity" => incident.severity,
        "impact_scope" => incident.impact_scope || "",
        "announcement" => incident.announcement || ""
      },
      as: "incident"
    )
  end

  defp load_verifications(ticket_id) do
    case Helpdesk.list_verifications(ticket_id) do
      {:ok, verifications} ->
        {verifications, []}

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.fetch_verifications", error, ticket_id: ticket_id)
        {[], ["検証結果の取得に失敗しました"]}
    end
  end

  defp error_message(:load_ticket), do: "チケットの取得に失敗しました"
  defp error_message(:load_users), do: "ユーザー一覧の取得に失敗しました"
  defp error_message(:ensure_conversations), do: "会話の初期化に失敗しました"
  defp error_message(:load_task_links), do: "関連タスクの取得に失敗しました"
  defp error_message(:load_ticket_relations), do: "関連チケットの取得に失敗しました"

  @impl Phoenix.LiveView
  def handle_event("link_task", %{"link" => %{"task_id" => task_id}}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case task_id |> to_string() |> Integer.parse() do
        {task_id, _rest} ->
          result =
            Tasks.create_ticket_task_link(
              %{
                ticket_id: socket.assigns.ticket.id,
                task_id: task_id
              },
              actor: socket.assigns.current_user
            )

          case result do
            {:ok, _link} ->
              {:noreply,
               socket
               |> put_flash(:info, "タスクを紐付けました")
               |> reload_task_links()}

            {:error, error} ->
              ErrorLog.log_error("ticket_live.show.link_task", error,
                ticket_id: socket.assigns.ticket.id,
                task_id: task_id
              )

              {:noreply, put_flash(socket, :error, "タスクの紐付けに失敗しました")}
          end

        :error ->
          {:noreply, put_flash(socket, :error, "タスクを選択してください")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("unlink_task", %{"link_id" => link_id}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case Integer.parse(link_id) do
        {link_id, _rest} ->
          with {:ok, %TicketTaskLink{} = link} <-
                 Tasks.get_ticket_task_link(link_id, socket.assigns.ticket.id, actor: socket.assigns.current_user),
               :ok <-
                 Tasks.destroy_ticket_task_link(link, actor: socket.assigns.current_user) do
            {:noreply,
             socket
             |> put_flash(:info, "タスクの紐付けを解除しました")
             |> reload_task_links()}
          else
            {:ok, nil} ->
              {:noreply, put_flash(socket, :error, "紐付けが見つかりません")}

            {:error, error} ->
              ErrorLog.log_error("ticket_live.show.unlink_task", error,
                ticket_id: socket.assigns.ticket.id,
                link_id: link_id
              )

              {:noreply, put_flash(socket, :error, "紐付けの解除に失敗しました")}
          end

        :error ->
          {:noreply, put_flash(socket, :error, "紐付けが見つかりません")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("link_ticket", %{"link" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case TicketRelations.create_link(
             socket.assigns.ticket,
             params["related_ticket_id"],
             params["relation_type"],
             socket.assigns.current_user
           ) do
        {:ok, _link} ->
          {:noreply,
           socket
           |> put_flash(:info, "関連チケットを追加しました")
           |> reload_ticket_relations()}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.link_ticket", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "関連チケットの追加に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("unlink_ticket", %{"link_id" => link_id}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case TicketRelations.delete_link(socket.assigns.ticket, link_id) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "関連チケットを解除しました")
           |> reload_ticket_relations()}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.unlink_ticket", error,
            ticket_id: socket.assigns.ticket.id,
            link_id: link_id
          )

          {:noreply, put_flash(socket, :error, "関連チケットの解除に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_status", %{"form" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      status_form = AshPhoenix.Form.validate(socket.assigns.status_form, params)
      {:noreply, assign(socket, :status_form, status_form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save_status", %{"form" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      params = Map.put(params, "actor_id", socket.assigns.current_user.id)

      case AshPhoenix.Form.submit(socket.assigns.status_form,
             params: params,
             action_opts: actor_action_opts(socket)
           ) do
        {:ok, ticket} ->
          ticket = load_ticket_product(ticket)

          status_form =
            ticket
            |> ticket_status_form(socket.assigns.current_user)
            |> to_form()

          update_form =
            ticket
            |> ticket_update_form(socket.assigns.current_user)
            |> to_form()

          {:noreply,
           socket
           |> put_flash(:info, "ステータスを更新しました")
           |> assign(:ticket, ticket)
           |> assign(:status_form, status_form)
           |> assign(:update_form, update_form)}

        {:error, form} ->
          socket =
            if stale_record_error?(form) do
              refresh_ticket_forms(socket)
            else
              socket
            end

          {:noreply,
           socket
           |> put_flash(:error, submit_error_message(form))
           |> assign(:status_form, form)}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_older_messages", %{"kind" => kind}, socket) do
    if forbidden_read?(socket, kind) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      before_id = message_oldest_id(socket, kind)
      conversation_id = conversation_id_for_kind(socket, kind)

      case fetch_messages(conversation_id, before_id, socket.assigns.current_user) do
        {:ok, {messages, has_more?, oldest_id}} ->
          next_oldest_id = oldest_id || before_id

          {:noreply,
           socket
           |> assign(message_has_more_key(kind), has_more?)
           |> assign(message_oldest_key(kind), next_oldest_id)
           |> stream(message_stream_name(kind), messages, at: -1)}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.load_older_messages", error, conversation_id: conversation_id)

          {:noreply, put_flash(socket, :error, "メッセージの取得に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("load_older_events", _params, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      before_id = socket.assigns.events_oldest_id

      case fetch_events(socket.assigns.ticket.id, before_id) do
        {:ok, {events, has_more?, oldest_id}} ->
          {:noreply,
           socket
           |> assign(:events_has_more?, has_more?)
           |> assign(:events_oldest_id, oldest_id || before_id)
           |> stream(:events, events, at: -1)}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.load_older_events", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "イベントの取得に失敗しました")}
      end
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
      params = Map.put(params, "actor_id", socket.assigns.current_user.id)

      case AshPhoenix.Form.submit(socket.assigns.update_form,
             params: params,
             action_opts: actor_action_opts(socket)
           ) do
        {:ok, ticket} ->
          ticket = load_ticket_product(ticket)

          status_form =
            ticket
            |> ticket_status_form(socket.assigns.current_user)
            |> to_form()

          update_form =
            ticket
            |> ticket_update_form(socket.assigns.current_user)
            |> to_form()

          {:noreply,
           socket
           |> put_flash(:info, "更新しました")
           |> assign(:ticket, ticket)
           |> assign(:status_form, status_form)
           |> assign(:update_form, update_form)}

        {:error, form} ->
          socket =
            if stale_record_error?(form) do
              refresh_ticket_forms(socket)
            else
              socket
            end

          {:noreply,
           socket
           |> put_flash(:error, submit_error_message(form))
           |> assign(:update_form, form)}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_verification", %{"verification" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.verification_form, params)
    {:noreply, assign(socket, :verification_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_verification", %{"verification" => params}, socket) do
    if socket.assigns.ticket.status != "resolved" do
      {:noreply, put_flash(socket, :error, "resolved 状態のチケットのみ検証結果を登録できます")}
    else
      params =
        params
        |> Map.put("ticket_id", socket.assigns.ticket.id)
        |> Map.put("verifier_id", socket.assigns.current_user.id)

      case AshPhoenix.Form.submit(socket.assigns.verification_form,
             params: params,
             action_opts: [actor: socket.assigns.current_user]
           ) do
        {:ok, verification} ->
          form =
            TicketVerification
            |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
            |> to_form(as: "verification")

          {:noreply,
           socket
           |> put_flash(:info, "検証結果を記録しました")
           |> assign(:verification_form, form)
           |> assign(:verifications, [verification | socket.assigns.verifications])}

        {:error, form} ->
          {:noreply,
           socket
           |> put_flash(:error, "検証結果の記録に失敗しました")
           |> assign(:verification_form, form)}
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
        |> AshPhoenix.Form.submit(
          params: message_params,
          action_opts: [actor: socket.assigns.current_user]
        )

      case submission do
        {:ok, message} ->
          ticket =
            case Helpdesk.get_ticket(socket.assigns.ticket.id) do
              {:ok, %Ticket{} = ticket} ->
                load_ticket_product(ticket)

              {:ok, nil} ->
                socket.assigns.ticket

              {:error, error} ->
                ErrorLog.log_error("ticket_live.show.reload_ticket", error, ticket_id: socket.assigns.ticket.id)

                socket.assigns.ticket
            end

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

  @impl Phoenix.LiveView
  def handle_event("start_edit_message", %{"message_id" => message_id}, socket) do
    with {:ok, id} <- parse_id(message_id),
         {:ok, %ConversationMessage{} = message} <- fetch_ticket_message(socket, id),
         true <- can_edit_message?(socket.assigns.current_user, message) do
      form =
        message
        |> AshPhoenix.Form.for_update(:edit, domain: Helpdesk, as: "message_edit")
        |> to_form()

      {:noreply,
       socket
       |> assign(:editing_message_id, message.id)
       |> assign(:edit_message_form, form)
       |> stream_insert(message_stream_name(message_kind(socket, message)), message)}
    else
      _result ->
        {:noreply, put_flash(socket, :error, "このメッセージは編集できません")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("cancel_edit_message", %{"message_id" => message_id}, socket) do
    with {:ok, id} <- parse_id(message_id),
         {:ok, %ConversationMessage{} = message} <- fetch_ticket_message(socket, id) do
      {:noreply,
       socket
       |> assign(:editing_message_id, nil)
       |> assign(:edit_message_form, nil)
       |> stream_insert(message_stream_name(message_kind(socket, message)), message)}
    else
      _result -> {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate_edit_message", %{"message_edit" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.edit_message_form, params)
    {:noreply, assign(socket, :edit_message_form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save_edit_message", %{"message_edit" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.edit_message_form,
           params: params,
           action_opts: [actor: socket.assigns.current_user]
         ) do
      {:ok, message} ->
        kind = message_kind(socket, message)

        {:noreply,
         socket
         |> assign(:editing_message_id, nil)
         |> assign(:edit_message_form, nil)
         |> put_flash(:info, "メッセージを更新しました")
         |> stream_insert(message_stream_name(kind), message)}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "メッセージの更新に失敗しました")
         |> assign(:edit_message_form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete_message", %{"message_id" => message_id}, socket) do
    with {:ok, id} <- parse_id(message_id),
         {:ok, %ConversationMessage{} = message} <- fetch_ticket_message(socket, id),
         true <- can_delete_message?(socket.assigns.current_user, message),
         {:ok, deleted} <-
           Helpdesk.soft_delete_message(message, actor: socket.assigns.current_user) do
      kind = message_kind(socket, deleted)

      socket =
        if socket.assigns.editing_message_id == deleted.id do
          socket
          |> assign(:editing_message_id, nil)
          |> assign(:edit_message_form, nil)
        else
          socket
        end

      {:noreply,
       socket
       |> put_flash(:info, "メッセージを削除しました")
       |> stream_delete(message_stream_name(kind), deleted)}
    else
      _result ->
        {:noreply, put_flash(socket, :error, "このメッセージは削除できません")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("promote_incident", %{"incident" => params}, socket) do
    if socket.assigns.current_user_external? do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case Helpdesk.promote_incident(socket.assigns.ticket, params, socket.assigns.current_user) do
        {:ok, _incident} ->
          {:noreply,
           socket
           |> put_flash(:info, "インシデントに昇格しました")
           |> reload_incident()}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "インシデントを操作する権限がありません")}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.promote_incident", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "インシデントへの昇格に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("update_incident", %{"incident" => params}, socket) do
    if socket.assigns.current_user_external? or is_nil(socket.assigns.incident) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case Helpdesk.update_incident(
             socket.assigns.incident,
             params,
             socket.assigns.current_user
           ) do
        {:ok, _incident} ->
          {:noreply,
           socket
           |> put_flash(:info, "インシデントを更新しました")
           |> reload_incident()}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "インシデントを操作する権限がありません")}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.update_incident", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "インシデントの更新に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("demote_incident", _params, socket) do
    if socket.assigns.current_user_external? or is_nil(socket.assigns.incident) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case Helpdesk.demote_incident(socket.assigns.incident, socket.assigns.current_user) do
        {:ok, _incident} ->
          {:noreply,
           socket
           |> put_flash(:info, "インシデントを降格しました")
           |> reload_incident()}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "インシデントを操作する権限がありません")}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.demote_incident", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "インシデントの降格に失敗しました")}
      end
    end
  end

  @impl Phoenix.LiveView
  def handle_event("add_incident_event", %{"incident_event" => params}, socket) do
    if socket.assigns.current_user_external? or is_nil(socket.assigns.incident) do
      {:noreply, put_flash(socket, :error, "アクセス権限がありません")}
    else
      case Helpdesk.add_incident_event(
             socket.assigns.incident,
             params,
             socket.assigns.current_user
           ) do
        {:ok, _event} ->
          {:noreply,
           socket
           |> put_flash(:info, "タイムラインを記録しました")
           |> reload_incident()}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "インシデントを操作する権限がありません")}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.show.add_incident_event", error, ticket_id: socket.assigns.ticket.id)

          {:noreply, put_flash(socket, :error, "タイムラインの記録に失敗しました")}
      end
    end
  end

  defp reload_incident(socket) do
    {incident, events} =
      load_incident(socket.assigns.ticket, socket.assigns.current_user_external?)

    socket
    |> assign(:incident, incident)
    |> assign(:incident_events, events)
    |> assign(:incident_form, incident_form(incident))
    |> assign(:incident_event_form, to_form(%{"phase" => "investigation", "body" => ""}, as: "incident_event"))
  end

  defp reload_task_links(socket) do
    case load_task_links(socket.assigns.ticket, socket.assigns.current_user) do
      {:ok, links, tasks} ->
        socket
        |> assign(:task_links, links)
        |> assign(:linkable_tasks, tasks)
        |> assign(:task_link_form, to_form(%{"task_id" => ""}, as: "link"))

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.reload_task_links", error, ticket_id: socket.assigns.ticket.id)

        put_flash(socket, :error, "関連タスクの取得に失敗しました")
    end
  end

  defp reload_ticket_relations(socket) do
    case load_ticket_relations(socket.assigns.ticket, socket.assigns.current_user) do
      {:ok, links, linkable_tickets} ->
        socket
        |> assign(:ticket_links, links)
        |> assign(:linkable_tickets, linkable_tickets)
        |> assign(
          :ticket_link_form,
          to_form(%{"related_ticket_id" => "", "relation_type" => "related"}, as: "link")
        )

      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.reload_ticket_relations", error, ticket_id: socket.assigns.ticket.id)

        put_flash(socket, :error, "関連チケットの取得に失敗しました")
    end
  end

  defp relation_options do
    [
      {"関連", "related"},
      {"再起票元", "reopened_from"},
      {"重複", "duplicate_of"},
      {"ブロックする", "blocks"},
      {"ブロックされる", "blocked_by"}
    ]
  end

  defp ticket_options(tickets) do
    Enum.map(tickets, fn ticket ->
      {"#{ticket.public_id} #{ticket.subject} (#{ticket.status})", ticket.id}
    end)
  end

  defp direction_label(:outgoing), do: "このチケットから"
  defp direction_label(:incoming), do: "このチケットへ"

  defp status_options(true) do
    [
      {"new", "new"},
      {"triage", "triage"},
      {"in_progress", "in_progress"},
      {"waiting", "waiting"},
      {"resolved", "resolved"},
      {"verified", "verified"},
      {"closed", "closed"}
    ]
  end

  defp status_options(false) do
    [
      {"new", "new"},
      {"triage", "triage"},
      {"in_progress", "in_progress"},
      {"waiting", "waiting"},
      {"resolved", "resolved"}
    ]
  end

  defp verification_result_options do
    [
      {"合格", "passed"},
      {"不合格", "failed"},
      {"要確認", "needs_review"}
    ]
  end

  defp verification_result_label("passed"), do: "合格"
  defp verification_result_label("failed"), do: "不合格"
  defp verification_result_label("needs_review"), do: "要確認"
  defp verification_result_label(value), do: value

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

  defp selectable_users(users) do
    Enum.filter(users, fn user ->
      Authorization.internal?(user) and user.status == "active"
    end)
  end

  defp task_options(tasks) do
    Enum.map(tasks, fn task ->
      {"#{task.public_id} #{task.title} (#{task.status})", task.id}
    end)
  end

  defp user_label(user), do: HelpdeskCommanderWeb.CurrentUser.display_label(user)

  defp product_label(%Product{name: name}), do: name
  defp product_label(_product), do: "-"

  defp load_ticket_product(%Ticket{} = ticket) do
    with {:ok, ticket} <- Helpdesk.load_ticket_product(ticket),
         {:ok, ticket} <- Helpdesk.load_ticket_stats(ticket) do
      ticket
    else
      {:error, error} ->
        ErrorLog.log_error("ticket_live.show.load_ticket_details", error, ticket_id: ticket.id)
        ticket
    end
  end

  defp refresh_ticket_forms(socket) do
    case Helpdesk.get_ticket(socket.assigns.ticket.id) do
      {:ok, %Ticket{} = ticket} ->
        ticket = load_ticket_product(ticket)

        status_form =
          ticket
          |> ticket_status_form(socket.assigns.current_user)
          |> to_form()

        update_form =
          ticket
          |> ticket_update_form(socket.assigns.current_user)
          |> to_form()

        socket
        |> assign(:ticket, ticket)
        |> assign(:status_form, status_form)
        |> assign(:update_form, update_form)

      _result ->
        socket
    end
  end

  defp submit_error_message(form) do
    cond do
      forbidden_error?(form) ->
        "アクセス権限がありません"

      stale_record_error?(form) ->
        "更新競合が発生しました。最新の内容を再読み込みしました。もう一度お試しください。"

      true ->
        "更新に失敗しました"
    end
  end

  defp stale_record_error?(%Phoenix.HTML.Form{source: source}), do: stale_record_error?(source)

  defp stale_record_error?(%AshPhoenix.Form{source: source, submit_errors: submit_errors}) do
    stale_error?(source) or
      submit_errors
      |> List.wrap()
      |> Enum.any?(&stale_error?/1)
  end

  defp stale_record_error?(_form), do: false

  defp stale_error?(%Ash.Changeset{errors: errors}), do: Enum.any?(errors, &stale_error?/1)

  defp stale_error?(%Ash.Error.Changes.StaleRecord{}), do: true

  defp stale_error?(%Ash.Error.Invalid{errors: errors}) do
    Enum.any?(errors, &stale_error?/1)
  end

  defp stale_error?({_field, %Ash.Error.Changes.StaleRecord{}}), do: true

  defp stale_error?({_field, %Ash.Error.Invalid{errors: errors}}) do
    Enum.any?(errors, &stale_error?/1)
  end

  defp stale_error?(_error), do: false

  defp forbidden_error?(%Phoenix.HTML.Form{source: source}), do: forbidden_error?(source)

  defp forbidden_error?(%AshPhoenix.Form{source: source, submit_errors: submit_errors}) do
    forbidden_error?(source) or
      submit_errors
      |> List.wrap()
      |> Enum.any?(&forbidden_error?/1)
  end

  defp forbidden_error?(%Ash.Changeset{errors: errors}), do: Enum.any?(errors, &forbidden_error?/1)

  defp forbidden_error?(%Ash.Error.Forbidden{}), do: true
  defp forbidden_error?(%Ash.Error.Forbidden.Policy{}), do: true

  defp forbidden_error?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &forbidden_error?/1)

  defp forbidden_error?({_field, {message, _vars}}) when is_binary(message) do
    String.contains?(message, "Forbidden") or String.contains?(message, "forbidden")
  end

  defp forbidden_error?({_field, error}), do: forbidden_error?(error)

  defp forbidden_error?(_error), do: false

  defp load_users(company_id) do
    case Accounts.list_users(company_id) do
      {:ok, users} ->
        sorted = Enum.sort_by(users, & &1.inserted_at, {:asc, DateTime})
        {:ok, sorted, Map.new(sorted, &{&1.id, &1})}

      {:error, error} ->
        {:error, {:load_users, error}}
    end
  end

  defp load_task_links(_ticket, actor) when is_nil(actor), do: {:ok, [], []}

  defp load_task_links(%Ticket{} = ticket, actor) do
    if Authorization.external?(actor) do
      {:ok, [], []}
    else
      do_load_task_links(ticket, actor)
    end
  end

  defp do_load_task_links(%Ticket{id: ticket_id, company_id: company_id}, actor) do
    with {:ok, links} <- Tasks.list_ticket_task_links(ticket_id, actor: actor),
         {:ok, tasks} <-
           Tasks.list_linkable_tasks(company_id, Enum.map(links, & &1.task_id), actor: actor) do
      {:ok, links, tasks}
    else
      {:error, error} -> {:error, {:load_task_links, error}}
    end
  end

  defp load_ticket_relations(%Ticket{} = ticket, actor) do
    if Authorization.external?(actor) do
      {:ok, [], []}
    else
      do_load_ticket_relations(ticket, actor)
    end
  end

  defp do_load_ticket_relations(%Ticket{} = ticket, actor) do
    with {:ok, links} <- TicketRelations.list_links(ticket, actor: actor),
         {:ok, linkable_tickets} <- TicketRelations.linkable_tickets(ticket) do
      {:ok, links, linkable_tickets}
    else
      {:error, error} -> {:error, {:load_ticket_relations, error}}
    end
  end

  defp ensure_conversations(%Ticket{} = ticket) do
    with {:ok, public} <- get_or_create_conversation(ticket, "internal_public"),
         {:ok, private} <- get_or_create_conversation(ticket, "internal_private") do
      {:ok, {public, private}}
    else
      {:error, error} -> {:error, {:ensure_conversations, error}}
    end
  end

  defp get_or_create_conversation(%Ticket{} = ticket, kind) do
    Helpdesk.ensure_conversation(ticket, kind)
  end

  defp fetch_messages(conversation_id, before_id, actor) do
    Helpdesk.list_messages(conversation_id, before_id, @messages_page_size, actor: actor)
  end

  defp fetch_events(ticket_id, before_id \\ nil) do
    Helpdesk.list_events(ticket_id, before_id, @events_page_size)
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

  defp message_kind(socket, %ConversationMessage{conversation_id: conversation_id}) do
    if conversation_id == socket.assigns.private_conversation.id, do: "private", else: "public"
  end

  defp fetch_ticket_message(socket, id) do
    conversation_ids =
      if socket.assigns.current_user_external? do
        [socket.assigns.public_conversation.id]
      else
        [socket.assigns.public_conversation.id, socket.assigns.private_conversation.id]
      end

    Helpdesk.get_message_in_conversations(id, conversation_ids, actor: socket.assigns.current_user)
  end

  defp can_edit_message?(%User{id: user_id}, %ConversationMessage{sender_id: user_id}), do: true
  defp can_edit_message?(_current_user, _message), do: false

  defp can_delete_message?(%User{id: user_id}, %ConversationMessage{sender_id: user_id}), do: true

  defp can_delete_message?(current_user, message),
    do: CurrentUser.admin?(current_user) and message.sender_id != nil

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _result -> :error
    end
  end

  defp parse_id(_value), do: :error

  defp message_type_options do
    [{"メッセージ", "message"}, {"メモ", "note"}, {"システム", "system"}]
  end

  defp message_type_label("message"), do: "メッセージ"
  defp message_type_label("note"), do: "メモ"
  defp message_type_label("system"), do: "システム"
  defp message_type_label(_type), do: "メッセージ"

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

  defp incident_severity_options do
    [{"SEV1 重大", "sev1"}, {"SEV2 高", "sev2"}, {"SEV3 中", "sev3"}, {"SEV4 低", "sev4"}]
  end

  defp incident_severity_label("sev1"), do: "SEV1"
  defp incident_severity_label("sev2"), do: "SEV2"
  defp incident_severity_label("sev3"), do: "SEV3"
  defp incident_severity_label("sev4"), do: "SEV4"
  defp incident_severity_label(_severity), do: "-"

  defp incident_phase_options do
    [
      {"調査", "investigation"},
      {"暫定対応", "mitigation"},
      {"復旧", "recovery"},
      {"監視", "monitoring"},
      {"振り返り", "retrospective"}
    ]
  end

  defp incident_phase_label("investigation"), do: "調査"
  defp incident_phase_label("mitigation"), do: "暫定対応"
  defp incident_phase_label("recovery"), do: "復旧"
  defp incident_phase_label("monitoring"), do: "監視"
  defp incident_phase_label("retrospective"), do: "振り返り"
  defp incident_phase_label(phase), do: phase

  defp event_label(%TicketEvent{event_type: "ticket_created"}), do: "チケット作成"
  defp event_label(%TicketEvent{event_type: "status_changed"}), do: "ステータス変更"
  defp event_label(%TicketEvent{event_type: "verification_submitted"}), do: "検証結果の記録"
  defp event_label(%TicketEvent{event_type: "incident_promoted"}), do: "インシデント昇格"
  defp event_label(%TicketEvent{event_type: "incident_demoted"}), do: "インシデント降格"
  defp event_label(%TicketEvent{event_type: "incident_timeline_updated"}), do: "インシデントタイムライン更新"

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

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
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
              <:item title="Product">{product_label(@ticket.product)}</:item>
              <:item title="Inserted at">{format_dt(@ticket.inserted_at)}</:item>
              <:item title="検証">{@ticket.verification_count || 0} 件</:item>
              <:item title="最終イベント">{format_dt(@ticket.latest_event_at)}</:item>
            </.list>

            <div class="mt-4">
              <h3 class="font-semibold">詳細</h3>
              <p class="mt-2 whitespace-pre-wrap text-sm opacity-80">{@ticket.description}</p>
            </div>
          </div>
        </div>

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 class="font-semibold">インシデント</h3>
              <span :if={@incident} class="badge badge-warning">
                {incident_severity_label(@incident.severity)}
              </span>
            </div>

            <%= cond do %>
              <% @incident && is_nil(@incident.demoted_at) -> %>
                <div class="mt-4 grid grid-cols-1 gap-4 text-sm sm:grid-cols-3">
                  <div>
                    <p class="text-xs uppercase tracking-wide opacity-60">影響範囲</p>
                    <p class="mt-1 whitespace-pre-wrap">{@incident.impact_scope || "-"}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-wide opacity-60">周知メモ</p>
                    <p class="mt-1 whitespace-pre-wrap">{@incident.announcement || "-"}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-wide opacity-60">昇格日時</p>
                    <p class="mt-1">{format_dt(@incident.promoted_at)}</p>
                  </div>
                </div>

                <%= if @can_approve? do %>
                  <.form for={@incident_form} id="incident-update-form" phx-submit="update_incident">
                    <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
                      <.input
                        field={@incident_form[:severity]}
                        type="select"
                        label="SEV"
                        options={incident_severity_options()}
                      />
                      <.input
                        field={@incident_form[:impact_scope]}
                        type="textarea"
                        label="影響範囲"
                      />
                      <.input
                        field={@incident_form[:announcement]}
                        type="textarea"
                        label="周知メモ"
                      />
                    </div>
                    <div class="mt-3 flex justify-end">
                      <.button type="submit">更新</.button>
                    </div>
                  </.form>

                  <.form
                    for={@incident_event_form}
                    id="incident-event-form"
                    phx-submit="add_incident_event"
                  >
                    <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-[12rem_1fr]">
                      <.input
                        field={@incident_event_form[:phase]}
                        type="select"
                        label="フェーズ"
                        options={incident_phase_options()}
                      />
                      <.input field={@incident_event_form[:body]} type="textarea" label="内容" />
                    </div>
                    <div class="mt-3 flex justify-end">
                      <.button type="submit">タイムラインに追加</.button>
                    </div>
                  </.form>

                  <form id="incident-demote-form" phx-submit="demote_incident" class="mt-3">
                    <.button type="submit" class="btn btn-ghost btn-sm text-error">
                      インシデントを降格
                    </.button>
                  </form>
                <% end %>

                <div id="incident-timeline" class="mt-6 space-y-3">
                  <p :if={@incident_events == []} class="text-sm opacity-70">
                    タイムラインはまだありません。
                  </p>
                  <div
                    :for={event <- @incident_events}
                    id={"incident-event-#{event.id}"}
                    class="rounded-box border border-base-200 p-3"
                  >
                    <div class="flex flex-wrap items-center justify-between gap-2 text-xs opacity-60">
                      <span>{incident_phase_label(event.phase)}</span>
                      <span>{format_dt(event.inserted_at)}</span>
                    </div>
                    <p class="mt-2 whitespace-pre-wrap text-sm">{event.body}</p>
                    <div class="mt-1 text-xs opacity-60">
                      {sender_label(@users_by_id, event.actor_id)}
                    </div>
                  </div>
                </div>
              <% @can_approve? -> %>
                <p class="mt-3 text-sm opacity-70">
                  {if @incident,
                    do: "降格済みのインシデントです。再度昇格できます。",
                    else: "チケットをインシデントに昇格できます。"}
                </p>

                <.form for={@incident_form} id="incident-promote-form" phx-submit="promote_incident">
                  <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <.input
                      field={@incident_form[:severity]}
                      type="select"
                      label="SEV"
                      options={incident_severity_options()}
                    />
                    <.input field={@incident_form[:impact_scope]} type="textarea" label="影響範囲" />
                    <.input field={@incident_form[:announcement]} type="textarea" label="周知メモ" />
                  </div>
                  <div class="mt-3 flex justify-end">
                    <.button type="submit" variant="primary">インシデントに昇格</.button>
                  </div>
                </.form>
              <% true -> %>
                <p class="mt-3 text-sm opacity-70">インシデント操作の権限がありません。</p>
            <% end %>
          </div>
        </div>

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">関連タスク</h3>

            <div id="ticket-task-links" class="mt-4 space-y-3">
              <div :if={@task_links == []} id="ticket-task-links-empty" class="text-sm opacity-70">
                関連タスクはまだありません。
              </div>

              <div
                :for={link <- @task_links}
                id={"ticket-task-link-#{link.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-base-200 p-3 text-sm"
              >
                <div>
                  <.link class="font-medium hover:underline" navigate={~p"/tasks/#{link.task.public_id}"}>
                    {link.task.title}
                  </.link>
                  <div class="mt-1 text-xs opacity-60">{link.task.public_id}</div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="rounded-full bg-base-200 px-3 py-1">{link.task.status}</span>
                  <span class="rounded-full bg-base-200 px-3 py-1">{link.task.priority}</span>
                  <button
                    type="button"
                    class="link text-error"
                    phx-click="unlink_task"
                    phx-value-link_id={link.id}
                  >
                    解除
                  </button>
                </div>
              </div>
            </div>

            <div :if={@linkable_tasks != []} class="mt-6">
              <.form for={@task_link_form} id="ticket-task-link-form" phx-submit="link_task">
                <.input
                  field={@task_link_form[:task_id]}
                  type="select"
                  label="タスクを紐付ける"
                  prompt="選択してください"
                  options={task_options(@linkable_tasks)}
                  required
                />

                <div class="mt-4 flex justify-end">
                  <.button type="submit" variant="primary">紐付ける</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">関連チケット</h3>

            <div id="ticket-links" class="mt-4 space-y-3">
              <div :if={@ticket_links == []} id="ticket-links-empty" class="text-sm opacity-70">
                関連チケットはまだありません。
              </div>

              <div
                :for={entry <- @ticket_links}
                id={"ticket-link-#{entry.link.id}"}
                class="flex flex-wrap items-center justify-between gap-3 rounded-box border border-base-200 p-3 text-sm"
              >
                <div>
                  <div class="text-xs opacity-60">
                    {direction_label(entry.direction)} / {entry.link.relation_type}
                  </div>
                  <.link class="font-medium hover:underline" navigate={~p"/tickets/#{entry.ticket.public_id}"}>
                    {entry.ticket.subject}
                  </.link>
                  <div class="mt-1 text-xs opacity-60">{entry.ticket.public_id}</div>
                </div>
                <div class="flex items-center gap-2">
                  <span class="rounded-full bg-base-200 px-3 py-1">{entry.ticket.status}</span>
                  <span class="rounded-full bg-base-200 px-3 py-1">{entry.ticket.priority}</span>
                  <button
                    type="button"
                    class="link text-error"
                    phx-click="unlink_ticket"
                    phx-value-link_id={entry.link.id}
                  >
                    解除
                  </button>
                </div>
              </div>
            </div>

            <div :if={@linkable_tickets != []} class="mt-6">
              <.form for={@ticket_link_form} id="ticket-link-form" phx-submit="link_ticket">
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-[1fr_auto]">
                  <.input
                    field={@ticket_link_form[:related_ticket_id]}
                    type="select"
                    label="関連チケット"
                    prompt="選択してください"
                    options={ticket_options(@linkable_tickets)}
                    required
                  />
                  <.input
                    field={@ticket_link_form[:relation_type]}
                    type="select"
                    label="関係"
                    options={relation_options()}
                  />
                </div>

                <div class="mt-4 flex justify-end">
                  <.button type="submit" variant="primary">関連付ける</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">ステータス更新</h3>
            <%= if @ticket.status in ["verified", "closed"] do %>
              <p class="text-sm opacity-70">verified/closed のため変更できません。</p>
            <% else %>
              <.form
                for={@status_form}
                id="ticket-status-form"
                phx-change="validate_status"
                phx-submit="save_status"
              >
                <.input
                  field={@status_form[:status]}
                  type="select"
                  label="Status"
                  options={status_options(@can_approve?)}
                />
                <.input
                  id="ticket-status-actor-id"
                  field={@status_form[:actor_id]}
                  type="hidden"
                  value={@current_user.id}
                />

                <div class="mt-6 flex justify-end">
                  <.button type="submit" variant="primary">更新</.button>
                </div>
              </.form>
            <% end %>
          </div>
        </div>

        <div :if={!@current_user_external?} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">優先度/担当者の確定</h3>
            <%= if @can_approve? do %>
              <.form
                for={@update_form}
                id="ticket-priority-form"
                phx-change="validate_update"
                phx-submit="save_update"
              >
                <.input
                  field={@update_form[:priority]}
                  type="select"
                  label="Priority"
                  options={[{"p1", "p1"}, {"p2", "p2"}, {"p3", "p3"}, {"p4", "p4"}]}
                />
                <.input
                  field={@update_form[:assignee_id]}
                  type="select"
                  label="Assignee"
                  prompt="未割り当て"
                  options={user_options(@assignable_users)}
                />
                <.input
                  id="ticket-update-actor-id"
                  field={@update_form[:actor_id]}
                  type="hidden"
                  value={@current_user.id}
                />

                <div class="mt-6 flex justify-end">
                  <.button type="submit" variant="primary">確定</.button>
                </div>
              </.form>
            <% else %>
              <p class="text-sm opacity-70">
                優先度・担当者の確定は管理者/リーダーのみ可能です。
              </p>
            <% end %>
          </div>
        </div>

        <div :if={@ticket.status in ["resolved", "verified", "closed"]} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <h3 class="font-semibold">検証</h3>
            <div id="ticket-verifications" class="mt-3 space-y-3">
              <div :if={@verifications == []} id="ticket-verifications-empty" class="text-sm opacity-70">
                まだ検証結果がありません。
              </div>

              <div
                :for={verification <- @verifications}
                id={"verification-#{verification.id}"}
                class="rounded-box border border-base-200 p-3 text-sm"
              >
                <div class="flex items-center justify-between text-xs text-base-content/60">
                  <span>{sender_label(@users_by_id, verification.verifier_id)}</span>
                  <span>{format_dt(verification.verified_at)}</span>
                </div>
                <div class="mt-2 font-medium">{verification_result_label(verification.result)}</div>
                <div :if={verification.notes not in [nil, ""]} class="mt-2 whitespace-pre-wrap opacity-80">
                  {verification.notes}
                </div>
              </div>
            </div>

            <%= if @ticket.status == "resolved" do %>
              <div class="mt-6">
                <h4 class="font-medium">検証結果を入力</h4>
                <.form
                  for={@verification_form}
                  id="ticket-verification-form"
                  phx-change="validate_verification"
                  phx-submit="save_verification"
                >
                  <.input
                    id="verification_result"
                    name="verification[result]"
                    field={@verification_form[:result]}
                    type="select"
                    label="結果"
                    options={verification_result_options()}
                  />
                  <.input
                    id="verification_notes"
                    name="verification[notes]"
                    field={@verification_form[:notes]}
                    type="textarea"
                    label="確認メモ"
                  />
                  <.input
                    id="verification_verifier_id"
                    name="verification[verifier_id]"
                    field={@verification_form[:verifier_id]}
                    type="hidden"
                    value={@current_user.id}
                  />
                  <.input
                    id="verification_ticket_id"
                    name="verification[ticket_id]"
                    field={@verification_form[:ticket_id]}
                    type="hidden"
                    value={@ticket.id}
                  />

                  <div class="mt-6 flex justify-end">
                    <.button type="submit" variant="primary">検証結果を記録</.button>
                  </div>
                </.form>
              </div>
            <% end %>
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

              <div :for={{id, message} <- @streams.public_messages} id={id}>
                <.message_item
                  message={message}
                  users_by_id={@users_by_id}
                  current_user={@current_user}
                  editing_message_id={@editing_message_id}
                  edit_message_form={@edit_message_form}
                />
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

              <div :for={{id, message} <- @streams.private_messages} id={id}>
                <.message_item
                  message={message}
                  users_by_id={@users_by_id}
                  current_user={@current_user}
                  editing_message_id={@editing_message_id}
                  edit_message_form={@edit_message_form}
                />
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
                    options={user_options(@assignable_users)}
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
                  options={user_options(@assignable_users)}
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

  attr :message, :map, required: true
  attr :users_by_id, :map, required: true
  attr :current_user, :any, required: true
  attr :editing_message_id, :any, default: nil
  attr :edit_message_form, :any, default: nil

  defp message_item(assigns) do
    ~H"""
    <div class="rounded-box border border-base-200 p-4">
      <div class="flex items-center justify-between text-xs text-base-content/60">
        <span>{sender_label(@users_by_id, @message.sender_id)}</span>
        <span>{format_dt(@message.inserted_at)}</span>
      </div>

      <%= if @editing_message_id == @message.id and @edit_message_form do %>
        <.form
          for={@edit_message_form}
          id={"message-edit-#{@message.id}"}
          phx-change="validate_edit_message"
          phx-submit="save_edit_message"
        >
          <.input field={@edit_message_form[:body]} type="textarea" label="本文" />
          <.input
            field={@edit_message_form[:message_type]}
            type="select"
            label="種別"
            options={message_type_options()}
          />
          <div class="mt-3 flex justify-end gap-2">
            <.button type="submit" variant="primary">保存</.button>
            <.button
              type="button"
              phx-click="cancel_edit_message"
              phx-value-message_id={@message.id}
            >
              キャンセル
            </.button>
          </div>
        </.form>
      <% else %>
        <p class="mt-3 whitespace-pre-wrap text-sm">{@message.body}</p>

        <div :if={map_size(@message.meta || %{}) > 0} class="mt-2 text-xs opacity-70">
          メタ: {format_meta(@message.meta)}
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-2 text-xs">
          <span class="badge badge-ghost badge-sm">{message_type_label(@message.message_type)}</span>
          <span :if={@message.edited_at} class="opacity-60">
            編集済み {format_dt(@message.edited_at)}
          </span>
          <div class="ml-auto flex gap-1">
            <.button
              :if={can_edit_message?(@current_user, @message)}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="start_edit_message"
              phx-value-message_id={@message.id}
            >
              編集
            </.button>
            <.button
              :if={can_delete_message?(@current_user, @message)}
              type="button"
              class="btn btn-ghost btn-xs text-error"
              phx-click="delete_message"
              phx-value-message_id={@message.id}
            >
              削除
            </.button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_meta(meta) when is_map(meta) do
    meta
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end

  defp format_dt(nil), do: "-"

  defp format_dt(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
