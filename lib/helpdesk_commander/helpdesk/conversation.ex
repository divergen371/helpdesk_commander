defmodule HelpdeskCommander.Helpdesk.Conversation do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "conversations"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :kind, :string,
      allow_nil?: false,
      constraints: [match: ~r/^(internal_public|internal_private)$/],
      public?: true

    attribute :external_provider, :string, public?: true
    attribute :external_ref, :string, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :ticket, HelpdeskCommander.Helpdesk.Ticket do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :created_by, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_ticket_kind, [:ticket_id, :kind]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:ticket_id, :kind, :created_by_id, :external_provider, :external_ref, :company_id]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket
    end
  end
end
