defmodule HelpdeskCommander.Helpdesk.SlaPolicy do
  @moduledoc """
  優先度ごとの SLA 目標時間（分）を保持する。

  会社ごとに 1 優先度 1 レコード。未設定の優先度は `HelpdeskCommander.Helpdesk.Sla`
  の既定値を使う。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sla_policies"
    repo HelpdeskCommander.Repo

    references do
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

    attribute :priority, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(p1|p2|p3|p4)$/]

    attribute :first_response_minutes, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :mitigation_minutes, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :resolution_minutes, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :restoration_minutes, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_priority, [:company_id, :priority]
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if expr(
                     company_id == ^actor(:company_id) and
                       ^actor(:role) in ["admin", "leader"]
                   )
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :company_id,
        :priority,
        :first_response_minutes,
        :mitigation_minutes,
        :resolution_minutes,
        :restoration_minutes
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :first_response_minutes,
        :mitigation_minutes,
        :resolution_minutes,
        :restoration_minutes
      ]
    end
  end
end
