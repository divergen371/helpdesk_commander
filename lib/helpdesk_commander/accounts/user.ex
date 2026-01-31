defmodule HelpdeskCommander.Accounts.User do
  use Ash.Resource,
    domain: HelpdeskCommander.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :email, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :role, :string, allow_nil?: false, default: "user"

    timestamps()
  end

  identities do
    identity :unique_email, [:email]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:email, :name, :role]
    end

    update :update do
      accept [:email, :name, :role]
    end
  end
end
