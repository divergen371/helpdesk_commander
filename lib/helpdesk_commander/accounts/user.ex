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

    attribute :email, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 255]

    attribute :login_id, :string,
      allow_nil?: true,
      public?: true,
      constraints: [min_length: 3, max_length: 32, match: ~r/^[a-z0-9_-]+$/]

    attribute :display_name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 100]

    attribute :password_hash, :string, allow_nil?: true, sensitive?: true
    attribute :status, :string, allow_nil?: false, default: "pending"
    attribute :role, :string, allow_nil?: false, default: "user"

    timestamps()
  end

  identities do
    identity :unique_company_email, [:company_id, :email]
    identity :unique_company_login_id, [:company_id, :login_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:company_id, :email, :display_name, :role, :status, :login_id]

      change HelpdeskCommander.Accounts.User.Changes.NormalizeFields
      change HelpdeskCommander.Accounts.User.Changes.DefaultDisplayName
    end

    update :update do
      require_atomic? false
      accept [:email, :display_name, :role, :status, :login_id]

      change HelpdeskCommander.Accounts.User.Changes.NormalizeFields
    end

    update :register do
      require_atomic? false
      argument :password, :string, allow_nil?: false, sensitive?: true
      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true

      accept [:display_name]
      change set_context(%{strategy_name: :password})

      change HelpdeskCommander.Accounts.User.Changes.NormalizeFields
      change HelpdeskCommander.Accounts.User.Changes.HashPassword
    end

    update :set_password do
      require_atomic? false
      argument :password, :string, allow_nil?: false, sensitive?: true
      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true
      change set_context(%{strategy_name: :password})
      change HelpdeskCommander.Accounts.User.Changes.HashPassword
      change AshAuthentication.Strategy.Password.HashPasswordChange
    end

    update :approve do
      change set_attribute(:status, "active")
    end

    update :set_login_id do
      require_atomic? false
      accept [:login_id]

      change HelpdeskCommander.Accounts.User.Changes.NormalizeFields
    end
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end
end
