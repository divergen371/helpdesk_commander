defmodule HelpdeskCommander.Helpdesk.ChatMessageLink do
  @moduledoc """
  会話メッセージと外部チャットメッセージの対応。

  外部メッセージ ID の一意制約で、Slack の再送や Oban の再試行による重複を取り除く。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "chat_message_links"
    repo HelpdeskCommander.Repo

    references do
      reference :conversation_message, on_delete: :delete
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
    attribute :external_message_id, :string, allow_nil?: false, public?: true

    attribute :direction, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(outbound|inbound)$/]

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :conversation_message, HelpdeskCommander.Helpdesk.ConversationMessage do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_external, [:provider, :channel_id, :external_message_id]
    identity :unique_message, [:conversation_message_id, :provider]
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :company_id,
        :conversation_message_id,
        :provider,
        :channel_id,
        :external_message_id,
        :direction
      ]
    end
  end
end
