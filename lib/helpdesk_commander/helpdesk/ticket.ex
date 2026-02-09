defmodule HelpdeskCommander.Helpdesk.Ticket do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  import Ash.Query

  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Support.PublicId

  postgres do
    table "tickets"
    repo HelpdeskCommander.Repo
    migration_types public_id: {:string, 32}
  end

  defp create_conversation(ticket, actor_id, kind) do
    Conversation
    |> Ash.Changeset.for_create(:create, %{
      ticket_id: ticket.id,
      kind: kind,
      created_by_id: actor_id,
      company_id: ticket.company_id
    })
    |> Ash.create!(domain: HelpdeskCommander.Helpdesk)
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :public_id, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [max_length: 32],
      default: &PublicId.generate/0

    attribute :subject, :string, allow_nil?: false, public?: true
    attribute :description, :string
    attribute :type, :string, allow_nil?: false, default: "question"
    attribute :status, :string, allow_nil?: false, default: "new"
    attribute :priority, :string, allow_nil?: false, default: "p3"

    attribute :visibility_scope, :string,
      allow_nil?: false,
      default: "company",
      constraints: [match: ~r/^(company|global_pending|global)$/]

    attribute :visibility_decided_at, :utc_datetime_usec
    attribute :impact, :string
    attribute :urgency, :string
    attribute :first_response_at, :utc_datetime_usec
    attribute :resolved_at, :utc_datetime_usec
    attribute :verified_at, :utc_datetime_usec
    attribute :closed_at, :utc_datetime_usec
    attribute :latest_message_at, :utc_datetime_usec
    attribute :lock_version, :integer, allow_nil?: false, default: 1

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :requester, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :assignee, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end

    belongs_to :visibility_decided_by, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end

    has_many :messages, HelpdeskCommander.Helpdesk.TicketMessage do
      destination_attribute :ticket_id
      public? true
    end

    has_many :conversations, HelpdeskCommander.Helpdesk.Conversation do
      destination_attribute :ticket_id
      public? true
    end

    has_many :events, HelpdeskCommander.Helpdesk.TicketEvent do
      destination_attribute :ticket_id
      public? true
    end
  end

  identities do
    identity :unique_public_id, [:public_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :company_id,
        :subject,
        :description,
        :type,
        :status,
        :priority,
        :visibility_scope,
        :visibility_decided_by_id,
        :visibility_decided_at,
        :impact,
        :urgency,
        :requester_id,
        :assignee_id
      ]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromRequester

      change after_action(fn changeset, ticket, _context ->
               actor_id =
                 Ash.Changeset.get_attribute(changeset, :requester_id) || ticket.requester_id

               _public = ensure_conversation(ticket, actor_id, "internal_public")
               _private = ensure_conversation(ticket, actor_id, "internal_private")

               _event =
                 TicketEvent
                 |> Ash.Changeset.for_create(:create, %{
                   event_type: "ticket_created",
                   data: %{},
                   ticket_id: ticket.id,
                   actor_id: actor_id,
                   company_id: ticket.company_id
                 })
                 |> Ash.create!(domain: HelpdeskCommander.Helpdesk)

               {:ok, ticket}
             end)
    end

    update :update do
      accept [
        :company_id,
        :subject,
        :description,
        :type,
        :status,
        :priority,
        :visibility_scope,
        :visibility_decided_by_id,
        :visibility_decided_at,
        :impact,
        :urgency,
        :first_response_at,
        :resolved_at,
        :verified_at,
        :closed_at,
        :latest_message_at,
        :requester_id,
        :assignee_id
      ]
    end
  end

  defp ensure_conversation(ticket, actor_id, kind) do
    conversation_result =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == ^kind)
      |> Ash.read_one(domain: HelpdeskCommander.Helpdesk)

    case conversation_result do
      {:ok, nil} ->
        create_conversation(ticket, actor_id, kind)

      {:ok, conversation} ->
        conversation

      _result ->
        create_conversation(ticket, actor_id, kind)
    end
  end
end
