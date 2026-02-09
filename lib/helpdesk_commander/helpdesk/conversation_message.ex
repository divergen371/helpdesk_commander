defmodule HelpdeskCommander.Helpdesk.ConversationMessage do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent

  postgres do
    table "conversation_messages"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :message_type, :string, allow_nil?: false, default: "message", public?: true
    attribute :body, :string, allow_nil?: false, public?: true
    attribute :body_format, :string, allow_nil?: false, default: "plain", public?: true
    attribute :meta, :map, allow_nil?: false, default: %{}, public?: true
    attribute :deleted_at, :utc_datetime_usec

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :conversation, HelpdeskCommander.Helpdesk.Conversation do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :sender, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:body, :conversation_id, :sender_id, :message_type, :body_format, :meta, :company_id]

      change fn changeset, _context ->
        assign_company_from_conversation(changeset)
      end

      change after_action(fn _changeset, message, _context ->
               conversation =
                 Ash.get!(Conversation, message.conversation_id, domain: Helpdesk)

               ticket =
                 Ash.get!(Ticket, %{id: conversation.ticket_id}, domain: Helpdesk)

               ticket
               |> Ash.Changeset.for_update(:update, %{
                 latest_message_at: message.inserted_at || DateTime.utc_now()
               })
               |> Ash.update!(domain: Helpdesk)

               _event =
                 TicketEvent
                 |> Ash.Changeset.for_create(:create, %{
                   event_type: "message_posted",
                   data: %{conversation_kind: conversation.kind},
                   ticket_id: ticket.id,
                   actor_id: message.sender_id,
                   company_id: ticket.company_id
                 })
                 |> Ash.create!(domain: Helpdesk)

               {:ok, message}
             end)
    end
  end

  defp assign_company_from_conversation(changeset) do
    case Ash.Changeset.get_attribute(changeset, :company_id) do
      nil ->
        conversation_id = Ash.Changeset.get_attribute(changeset, :conversation_id)

        case conversation_id &&
               Ash.get(Conversation, %{id: conversation_id}, domain: Helpdesk) do
          {:ok, nil} ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "会話から会社情報を特定できません"
            )

          {:ok, conversation} ->
            Ash.Changeset.change_attribute(changeset, :company_id, conversation.company_id)

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "会話から会社情報を特定できません"
            )
        end

      _company_id ->
        changeset
    end
  end
end
