defmodule HelpdeskCommander.Helpdesk.Product do
  use Ash.Resource,
    domain: HelpdeskCommander.Helpdesk,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "products"
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
    attribute :description, :string, public?: true

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

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :description, :company_id]
    end

    update :update do
      accept [:name, :description]
    end
  end
end
