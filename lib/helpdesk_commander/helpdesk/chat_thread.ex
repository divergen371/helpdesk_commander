defmodule HelpdeskCommander.Helpdesk.ChatThread do
  @moduledoc """
  チケットと外部チャットのスレッド対応。

  Slack では 1 チケットにつき 1 スレッドを作り、`thread_ts` で返信を紐付ける。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chat_threads"
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

    attribute :provider, :string,
      allow_nil?: false,
      default: "slack",
      public?: true,
      constraints: [match: ~r/^[a-z]+$/]

    attribute :channel_id, :string, allow_nil?: false, public?: true
    attribute :thread_ts, :string, allow_nil?: false, public?: true

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
  end

  identities do
    identity :unique_thread, [:provider, :channel_id, :thread_ts]
    identity :unique_ticket, [:ticket_id, :provider]
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
      accept [:company_id, :ticket_id, :provider, :channel_id, :thread_ts]
    end

    update :update do
      require_atomic? false
      accept [:channel_id, :thread_ts]
    end
  end
end
