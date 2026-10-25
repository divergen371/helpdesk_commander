defmodule HelpdeskCommander.Repo.Migrations.AddTaskEventsCascadeDelete do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE task_events DROP CONSTRAINT task_events_task_id_fkey")

    execute("""
    ALTER TABLE task_events
    ADD CONSTRAINT task_events_task_id_fkey
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
    """)
  end

  def down do
    execute("ALTER TABLE task_events DROP CONSTRAINT task_events_task_id_fkey")

    execute("""
    ALTER TABLE task_events
    ADD CONSTRAINT task_events_task_id_fkey
    FOREIGN KEY (task_id) REFERENCES tasks(id)
    """)
  end
end
