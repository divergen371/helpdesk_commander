defmodule HelpdeskCommander.Helpdesk.TicketAttachment do
  @moduledoc """
  チケットに添付されたファイルのメタデータ。

  実体はローカルディスクに保存し、このリソースは保存キー・ハッシュ・スキャン状態を持つ。
  ファイル名は PII を含み得るため暗号化する。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "ticket_attachments"
    repo HelpdeskCommander.Repo

    references do
      reference :ticket, on_delete: :delete
      reference :company, on_delete: :delete
      reference :uploaded_by, on_delete: :nilify
    end
  end

  cloak do
    vault(HelpdeskCommander.Vault)
    attributes([:filename])
    decrypt_by_default([:filename])
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

    attribute :filename, :string, allow_nil?: false, public?: true
    attribute :content_type, :string, allow_nil?: false, public?: true
    attribute :byte_size, :integer, allow_nil?: false, public?: true
    attribute :sha256, :string, allow_nil?: false, public?: true
    attribute :storage_key, :string, allow_nil?: false, public?: true

    attribute :scan_status, :string,
      allow_nil?: false,
      default: "pending",
      public?: true,
      constraints: [match: ~r/^(pending|clean|infected|failed|skipped)$/]

    attribute :scan_note, :string, public?: true
    attribute :scanned_at, :utc_datetime_usec, public?: true

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

    belongs_to :uploaded_by, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
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

    policy action(:destroy) do
      authorize_if expr(uploaded_by_id == ^actor(:id) or ^actor(:role) in ["admin", "leader"])
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :company_id,
        :ticket_id,
        :uploaded_by_id,
        :filename,
        :content_type,
        :byte_size,
        :sha256,
        :storage_key,
        :scan_status,
        :scan_note,
        :scanned_at
      ]
    end

    update :mark_scan do
      require_atomic? false
      accept [:scan_status, :scan_note, :scanned_at]
    end
  end
end
