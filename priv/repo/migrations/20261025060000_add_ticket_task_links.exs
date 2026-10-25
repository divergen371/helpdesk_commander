defmodule HelpdeskCommander.Repo.Migrations.AddTicketTaskLinks do
  use Ecto.Migration

  def change do
    create table(:ticket_task_links) do
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :company_id, references(:companies, on_delete: :delete_all), null: false
      add :relation_type, :text, null: false, default: "related"

      timestamps()
    end

    create unique_index(:ticket_task_links, [:ticket_id, :task_id])
    create index(:ticket_task_links, [:company_id])
    create index(:ticket_task_links, [:task_id])
  end
end
