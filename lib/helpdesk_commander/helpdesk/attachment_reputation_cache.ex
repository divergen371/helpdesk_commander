defmodule HelpdeskCommander.Helpdesk.AttachmentReputationCache do
  @moduledoc """
  添付ファイルの SHA256 外部レピュテーション照会キャッシュ（HC-41）。

  同一ハッシュの再照会を抑止するため、TTL 付きで判定結果（`infected` / `unknown`）を保持する。
  エラー（`fail-open`）はキャッシュしない。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "attachment_reputation_cache"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :sha256, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^[a-f0-9]{64}$/]

    attribute :verdict, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(infected|unknown)$/]

    attribute :provider, :string, allow_nil?: false, public?: true
    attribute :detail, :string, public?: true
    attribute :checked_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true

    timestamps()
  end

  identities do
    identity :unique_sha256, [:sha256]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:sha256, :verdict, :provider, :detail, :checked_at, :expires_at]
      upsert? true
      upsert_identity :unique_sha256
      upsert_fields [:verdict, :provider, :detail, :checked_at, :expires_at]
    end
  end
end
