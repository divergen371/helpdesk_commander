defmodule HelpdeskCommander.Helpdesk.TicketEvent do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ticket_events"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :event_type, :string, allow_nil?: false, public?: true
    attribute :data, :map, allow_nil?: false, default: %{}, public?: true

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

    belongs_to :actor, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:event_type, :data, :ticket_id, :actor_id, :company_id]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket
    end
  end
end
