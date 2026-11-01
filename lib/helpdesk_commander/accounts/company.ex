defmodule HelpdeskCommander.Accounts.Company do
  use Ash.Resource,
    domain: HelpdeskCommander.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshCloak]

  postgres do
    table "companies"
    repo HelpdeskCommander.Repo
  end

  cloak do
    vault(HelpdeskCommander.Vault)
    attributes([:name])
    decrypt_by_default([:name])
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :name_hash, :binary, allow_nil?: false, sensitive?: true, public?: false
    attribute :company_code_hash, :binary, allow_nil?: false
    attribute :status, :string, allow_nil?: false, default: "active", public?: true

    timestamps()
  end

  identities do
    identity :unique_company_code_hash, [:company_code_hash]
    identity :unique_company_name, [:name_hash]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :status]
      argument :company_code, :string, allow_nil?: false

      change HelpdeskCommander.Accounts.Company.Changes.HashCompanyCode
      change HelpdeskCommander.Accounts.Company.Changes.HashName
    end

    update :update do
      require_atomic? false
      accept [:name, :status]

      change HelpdeskCommander.Accounts.Company.Changes.HashName
    end
  end
end
