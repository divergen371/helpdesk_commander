defmodule HelpdeskCommander.Tasks.Task do
  use Ash.Resource,
    domain: HelpdeskCommander.Tasks,
    data_layer: AshPostgres.DataLayer

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
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

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 200]

    attribute :description, :string,
      public?: true,
      constraints: [max_length: 10_000]

    attribute :status, :string,
      allow_nil?: false,
      default: "todo",
      constraints: [match: ~r/^(todo|in_progress|done)$/]

    attribute :priority, :string,
      allow_nil?: false,
      default: "medium",
      constraints: [match: ~r/^(low|medium|high)$/]

    attribute :due_date, :date
    attribute :lock_version, :integer, allow_nil?: false, default: 1

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

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
      accept [:title, :description, :status, :priority, :due_date, :assignee_id, :company_id]

      change HelpdeskCommander.Tasks.Task.Changes.NormalizeFields
      change HelpdeskCommander.Tasks.Task.Changes.ValidateAssignee
    end

    update :update do
      require_atomic? false

      accept [:title, :description, :status, :due_date, :assignee_id]

      change HelpdeskCommander.Tasks.Task.Changes.NormalizeFields
      change HelpdeskCommander.Tasks.Task.Changes.ValidateAssignee
      change optimistic_lock(:lock_version)
    end

    update :set_priority do
      require_atomic? false

      argument :actor_id, HelpdeskCommander.Types.BigInt, allow_nil?: false
      argument :priority, :string, allow_nil?: false

      change set_attribute(:priority, arg(:priority))
      change optimistic_lock(:lock_version)

      change fn changeset, _context ->
        actor_id = Ash.Changeset.get_argument(changeset, :actor_id)

        case Ash.get(User, %{id: actor_id}, domain: HelpdeskCommander.Accounts) do
          {:ok, %User{} = actor} ->
            if Authorization.same_company?(actor, changeset.data.company_id) do
              changeset
            else
              Ash.Changeset.add_error(changeset,
                field: :actor_id,
                message: "別会社のタスクは変更できません"
              )
            end

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :actor_id,
              message: "実行者が見つかりません"
            )
        end
      end

      change after_action(fn changeset, task, _context ->
               previous = changeset.data
               new_priority = task.priority

               data = %{field: "priority", from: previous.priority, to: new_priority}

               _event =
                 HelpdeskCommander.Tasks.TaskEvent
                 |> Ash.Changeset.for_create(:create, %{
                   event_type: "priority_changed",
                   data: data,
                   task_id: task.id,
                   actor_id: Ash.Changeset.get_argument(changeset, :actor_id),
                   company_id: task.company_id
                 })
                 |> Ash.create!(domain: HelpdeskCommander.Tasks)

               {:ok, task}
             end)

      accept []
    end
  end
end
