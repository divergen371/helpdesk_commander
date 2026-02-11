defmodule HelpdeskCommander.Helpdesk.TicketLink do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket

  @relation_regex ~r/^(reopened_from|related|duplicate_of|blocks|blocked_by)$/

  postgres do
    table "ticket_links"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :relation_type, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @relation_regex]

    timestamps()
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

    belongs_to :related_ticket, HelpdeskCommander.Helpdesk.Ticket do
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
    identity :unique_relation, [:ticket_id, :related_ticket_id, :relation_type]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:ticket_id, :related_ticket_id, :relation_type, :created_by_id]

      change AssignCompanyFromTicket
    end
  end
end
