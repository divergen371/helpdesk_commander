defmodule HelpdeskCommander.Helpdesk.AttachmentHashRule do
  @moduledoc """
  添付ファイルの SHA256 許可・拒否リスト（HC-24）。

  `company_id` が nil の行は全体ルール、値がある行はその会社だけに適用する。
  拒否（deny）は許可（allow）より優先する。
  """

  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "attachment_hash_rules"
    repo HelpdeskCommander.Repo

    references do
      reference :company, on_delete: :delete
    end
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

    attribute :action, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/^(allow|deny)$/]

    attribute :note, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:company_id, :sha256, :action, :note]
    end

    update :update do
      accept [:action, :note]
    end
  end
end
