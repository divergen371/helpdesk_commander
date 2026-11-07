defmodule HelpdeskCommander.Helpdesk.AttachmentSignature do
  @moduledoc """
  添付スキャナのシグネチャ状態（エンジン・版・日時・最終更新結果）を保持する（HC-22）。

  単一の論理レコード（name = "clamav"）を upsert する。鮮度判定は
  `HelpdeskCommander.Attachments.Signatures` が行う。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "attachment_signatures"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :name, :string, allow_nil?: false, default: "clamav", public?: true
    attribute :engine, :string, public?: true
    attribute :version, :string, public?: true
    attribute :signature_at, :utc_datetime_usec, public?: true
    attribute :checked_at, :utc_datetime_usec, public?: true

    attribute :status, :string,
      allow_nil?: false,
      default: "unknown",
      public?: true,
      constraints: [match: ~r/^(ok|error|unknown)$/]

    attribute :last_error, :string, public?: true

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :engine, :version, :signature_at, :checked_at, :status, :last_error]
    end

    update :record do
      accept [:engine, :version, :signature_at, :checked_at, :status, :last_error]
    end
  end
end
