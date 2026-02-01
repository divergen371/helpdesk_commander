defmodule HelpdeskCommander.Helpdesk.Ticket do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Support.PublicId

  postgres do
    table "tickets"
    repo HelpdeskCommander.Repo
    migration_types public_id: {:string, 32}
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

    has_many :messages, HelpdeskCommander.Helpdesk.TicketMessage do
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
        :subject,
        :description,
        :type,
        :status,
        :priority,
        :impact,
        :urgency,
        :requester_id,
        :assignee_id
      ]
    end

    update :update do
      accept [
        :subject,
        :description,
        :type,
        :status,
        :priority,
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
end
