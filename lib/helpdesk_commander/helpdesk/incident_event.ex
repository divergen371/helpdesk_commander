defmodule HelpdeskCommander.Helpdesk.IncidentEvent do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "incident_events"
    repo HelpdeskCommander.Repo

    references do
      reference :incident, on_delete: :delete
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

    attribute :phase, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(investigation|mitigation|recovery|monitoring|retrospective)$/]

    attribute :body, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :incident, HelpdeskCommander.Helpdesk.Incident do
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

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  actions do
    defaults [:read]

    create :create do
      accept [:incident_id, :phase, :body, :actor_id, :company_id]

      change HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromIncident
    end
  end
end
