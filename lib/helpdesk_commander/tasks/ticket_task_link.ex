defmodule HelpdeskCommander.Tasks.TicketTaskLink do
  use Ash.Resource,
    domain: HelpdeskCommander.Tasks,
    data_layer: AshPostgres.DataLayer

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task

  @relation_regex ~r/^(related|follow_up|root_cause)$/

  postgres do
    table "ticket_task_links"
    repo HelpdeskCommander.Repo
  end

  attributes do
    attribute :id, HelpdeskCommander.Types.BigInt,
      primary_key?: true,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true

    attribute :relation_type, :string,
      allow_nil?: false,
      default: "related",
      public?: true,
      constraints: [match: @relation_regex]

    timestamps()
  end

  relationships do
    belongs_to :company, HelpdeskCommander.Accounts.Company do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :ticket, Ticket do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end

    belongs_to :task, Task do
      attribute_type HelpdeskCommander.Types.BigInt
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_ticket_task, [:ticket_id, :task_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:ticket_id, :task_id, :relation_type]

      change fn changeset, _context ->
        ticket_id = Ash.Changeset.get_attribute(changeset, :ticket_id)
        task_id = Ash.Changeset.get_attribute(changeset, :task_id)

        existing_link_query =
          filter(
            Ash.Query.new(__MODULE__),
            ticket_id == ^ticket_id and task_id == ^task_id
          )

        with {:ok, %Ticket{company_id: company_id}} <-
               Ash.get(Ticket, %{id: ticket_id}, domain: Helpdesk),
             {:ok, %Task{company_id: ^company_id}} <-
               Ash.get(Task, %{id: task_id}, domain: Tasks),
             {:ok, nil} <- Ash.read_one(existing_link_query, domain: Tasks) do
          Ash.Changeset.change_attribute(changeset, :company_id, company_id)
        else
          {:ok, %TicketTaskLink{}} ->
            Ash.Changeset.add_error(changeset,
              field: :task_id,
              message: "既に紐付けられています"
            )

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :task_id,
              message: "同じ会社のチケットとタスクのみ紐付けできます"
            )
        end
      end
    end
  end
end
