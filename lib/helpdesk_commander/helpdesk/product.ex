defmodule HelpdeskCommander.Helpdesk.Product do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "products"
    repo HelpdeskCommander.Repo
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

    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 100]

    attribute :description, :string,
      public?: true,
      constraints: [max_length: 1000]

    attribute :active, :boolean, allow_nil?: false, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_company_name, [:company_id, :name]
  end

  code_interface do
    define :get_product, action: :read, get_by: [:id], not_found_error?: false
  end

  preparations do
    prepare HelpdeskCommander.Tenancy.Scope
  end

  changes do
    change HelpdeskCommander.Tenancy.Guard
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :active, :company_id]
    end

    update :update do
      require_atomic? false

      accept [:name, :description, :active]
    end
  end
end
