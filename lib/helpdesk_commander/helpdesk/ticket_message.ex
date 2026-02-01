defmodule HelpdeskCommander.Helpdesk.TicketMessage do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "ticket_messages"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :body, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :ticket, HelpdeskCommander.Helpdesk.Ticket do
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
    defaults [:read, :destroy]

    create :create do
      accept [:body, :ticket_id, :sender_id]
    end
  end
end
