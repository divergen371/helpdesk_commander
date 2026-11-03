defmodule HelpdeskCommander.Helpdesk.MonitoringAlert do
  @moduledoc """
  監視サービスから受信したアラートの状態。

  `source` と `fingerprint` の組で同一アラートを識別し、開いているチケットへの
  重複起票を抑止する。説明文は PII を含み得るため暗号化する。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "monitoring_alerts"
    repo HelpdeskCommander.Repo

    references do
      reference :ticket, on_delete: :nilify
      reference :company, on_delete: :delete
    end
  end

  cloak do
    vault(HelpdeskCommander.Vault)
    attributes([:description])
    decrypt_by_default([:description])
    encrypt_nil?(false)
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

    attribute :source, :string, allow_nil?: false, public?: true
    attribute :fingerprint, :string, allow_nil?: false, public?: true

    attribute :status, :string,
      allow_nil?: false,
      default: "firing",
      public?: true,
      constraints: [match: ~r/^(firing|resolved)$/]

    attribute :severity, :string,
      allow_nil?: false,
      default: "warning",
      public?: true,
      constraints: [match: ~r/^(critical|error|warning|info)$/]

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true

    attribute :first_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :last_seen_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :resolved_at, :utc_datetime_usec, public?: true

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
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_alert, [:source, :fingerprint]
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  policies do
    policy action_type([:read, :create, :update]) do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :company_id,
        :ticket_id,
        :source,
        :fingerprint,
        :status,
        :severity,
        :title,
        :description,
        :payload,
        :first_seen_at,
        :last_seen_at,
        :resolved_at
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :ticket_id,
        :status,
        :severity,
        :title,
        :description,
        :payload,
        :last_seen_at,
        :resolved_at
      ]
    end
  end
end
