defmodule HelpdeskCommander.Repo.Migrations.FixSchemaIssues do
  @moduledoc """
  Fix multiple DB schema issues:
  1. Add company_id to tasks and task_events (multi-tenant consistency)
  2. Add recommended indexes for tickets, ticket_links, conversation_messages
  3. Drop obsolete ticket_messages table
  4. Change lock_version from bigint to integer on tickets and tasks
  """

  use Ecto.Migration

  def up do
    # -------------------------------------------------------
    # 1. Add company_id to tasks
    # -------------------------------------------------------
    alter table(:tasks) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "tasks_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    # Backfill tasks.company_id from assignee's company
    execute("""
    UPDATE tasks AS t
    SET company_id = u.company_id
    FROM users AS u
    WHERE t.assignee_id = u.id AND t.company_id IS NULL;
    """)

    # For tasks without assignee, use the first company
    execute("""
    UPDATE tasks
    SET company_id = (SELECT id FROM companies ORDER BY id LIMIT 1)
    WHERE company_id IS NULL;
    """)

    execute("ALTER TABLE tasks ALTER COLUMN company_id SET NOT NULL;")

    create index(:tasks, [:company_id], name: "tasks_company_id_index")

    # -------------------------------------------------------
    # 1b. Add company_id to task_events
    # -------------------------------------------------------
    alter table(:task_events) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "task_events_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    # Backfill task_events.company_id from task
    execute("""
    UPDATE task_events AS te
    SET company_id = t.company_id
    FROM tasks AS t
    WHERE te.task_id = t.id AND te.company_id IS NULL;
    """)

    execute("ALTER TABLE task_events ALTER COLUMN company_id SET NOT NULL;")

    create index(:task_events, [:company_id], name: "task_events_company_id_index")

    # -------------------------------------------------------
    # 2. Recommended indexes
    # -------------------------------------------------------

    # tickets
    create index(:tickets, [:status], name: "tickets_status_index")
    create index(:tickets, [:priority], name: "tickets_priority_index")
    create index(:tickets, [:assignee_id, :status], name: "tickets_assignee_id_status_index")
    create index(:tickets, [:requester_id], name: "tickets_requester_id_index")

    create index(:tickets, ["latest_message_at DESC NULLS LAST"],
             name: "tickets_latest_message_at_desc_index"
           )

    # ticket_links (single-column indexes for reverse lookups)
    create index(:ticket_links, [:ticket_id], name: "ticket_links_ticket_id_index")

    create index(:ticket_links, [:related_ticket_id],
             name: "ticket_links_related_ticket_id_index"
           )

    # conversation_messages
    create index(:conversation_messages, [:sender_id, :inserted_at],
             name: "conversation_messages_sender_id_inserted_at_index"
           )

    # -------------------------------------------------------
    # 3. Drop obsolete ticket_messages table
    # -------------------------------------------------------
    drop_if_exists table(:ticket_messages)

    # -------------------------------------------------------
    # 4. Fix lock_version type (bigint -> integer)
    # -------------------------------------------------------
    execute("ALTER TABLE tickets ALTER COLUMN lock_version TYPE integer;")
    execute("ALTER TABLE tasks ALTER COLUMN lock_version TYPE integer;")
  end

  def down do
    # Restore lock_version to bigint
    execute("ALTER TABLE tasks ALTER COLUMN lock_version TYPE bigint;")
    execute("ALTER TABLE tickets ALTER COLUMN lock_version TYPE bigint;")

    # Recreate ticket_messages (minimal, data is lost)
    create table(:ticket_messages, primary_key: false) do
      add :id, :bigserial, null: false, primary_key: true
      add :body, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :ticket_id,
          references(:tickets,
            column: :id,
            name: "ticket_messages_ticket_id_fkey",
            type: :bigint,
            prefix: "public"
          ),
          null: false

      add :sender_id,
          references(:users,
            column: :id,
            name: "ticket_messages_sender_id_fkey",
            type: :bigint,
            prefix: "public"
          ),
          null: false
    end

    # Drop indexes
    drop_if_exists index(:conversation_messages, [:sender_id, :inserted_at],
                     name: "conversation_messages_sender_id_inserted_at_index"
                   )

    drop_if_exists index(:ticket_links, [:related_ticket_id],
                     name: "ticket_links_related_ticket_id_index"
                   )

    drop_if_exists index(:ticket_links, [:ticket_id], name: "ticket_links_ticket_id_index")

    drop_if_exists index(:tickets, ["latest_message_at DESC NULLS LAST"],
                     name: "tickets_latest_message_at_desc_index"
                   )

    drop_if_exists index(:tickets, [:requester_id], name: "tickets_requester_id_index")

    drop_if_exists index(:tickets, [:assignee_id, :status],
                     name: "tickets_assignee_id_status_index"
                   )

    drop_if_exists index(:tickets, [:priority], name: "tickets_priority_index")
    drop_if_exists index(:tickets, [:status], name: "tickets_status_index")

    # Drop task_events.company_id
    drop_if_exists index(:task_events, [:company_id], name: "task_events_company_id_index")
    execute("ALTER TABLE task_events DROP COLUMN company_id;")

    # Drop tasks.company_id
    drop_if_exists index(:tasks, [:company_id], name: "tasks_company_id_index")
    execute("ALTER TABLE tasks DROP COLUMN company_id;")
  end
end
