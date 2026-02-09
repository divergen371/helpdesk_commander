defmodule HelpdeskCommander.Accounts.Company do
  use Ash.Resource,
    domain: HelpdeskCommander.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "companies"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :company_code_hash, :binary, allow_nil?: false
    attribute :status, :string, allow_nil?: false, default: "active", public?: true

    timestamps()
  end

  identities do
    identity :unique_company_code_hash, [:company_code_hash]
    identity :unique_company_name, [:name]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :status]
      argument :company_code, :string, allow_nil?: false

      change HelpdeskCommander.Accounts.Company.Changes.HashCompanyCode
    end

    update :update do
      accept [:name, :status]
    end
  end
end
