defmodule HelpdeskCommander.Tasks.Task do
  use Ash.Resource,
    domain: HelpdeskCommander.Tasks,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Support.PublicId

  postgres do
    table "tasks"
    repo HelpdeskCommander.Repo
    migration_types public_id: {:string, 32}
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :public_id, :string,
      allow_nil?: false,
      writable?: false,
      public?: true,
      constraints: [max_length: 32],
      default: &PublicId.generate/0

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :description, :string
    attribute :status, :string, allow_nil?: false, default: "todo"
    attribute :priority, :string, allow_nil?: false, default: "medium"
    attribute :due_date, :date
    attribute :lock_version, :integer, allow_nil?: false, default: 1

    timestamps()
  end

  relationships do
    belongs_to :assignee, HelpdeskCommander.Accounts.User do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? true
      public? true
    end
  end

  identities do
    identity :unique_public_id, [:public_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :description, :status, :priority, :due_date, :assignee_id]
    end

    update :update do
      accept [:title, :description, :status, :priority, :due_date, :assignee_id]
    end
  end
end
