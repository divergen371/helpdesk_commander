defmodule HelpdeskCommander.Helpdesk.Incident do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "incidents"
    repo HelpdeskCommander.Repo

    references do
      reference :ticket, on_delete: :delete
      reference :company, on_delete: :delete
    end
  end

  multitenancy do
    strategy :attribute
    attribute :company_id
    global? true
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :severity, :string,
      allow_nil?: false,
      default: "sev3",
      public?: true,
      constraints: [match: ~r/^(sev1|sev2|sev3|sev4)$/]

    attribute :impact_scope, :string, public?: true
    attribute :announcement, :string, public?: true
    attribute :promoted_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :demoted_at, :utc_datetime_usec, public?: true

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

    belongs_to :promoted_by, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_ticket, [:ticket_id]
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  actions do
    defaults [:read]

    create :promote do
      accept [:ticket_id, :severity, :impact_scope, :announcement, :promoted_by_id, :company_id]

      change set_attribute(:promoted_at, &DateTime.utc_now/0)
      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket
    end

    update :update do
      require_atomic? false
      accept [:severity, :impact_scope, :announcement]
    end

    update :demote do
      require_atomic? false
      change set_attribute(:demoted_at, &DateTime.utc_now/0)
    end

    update :reactivate do
      require_atomic? false
      accept [:severity, :impact_scope, :announcement]
      change set_attribute(:demoted_at, nil)
      change set_attribute(:promoted_at, &DateTime.utc_now/0)
    end
  end
end
