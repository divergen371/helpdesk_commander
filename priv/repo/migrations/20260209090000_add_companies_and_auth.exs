defmodule HelpdeskCommander.Repo.Migrations.AddCompaniesAndAuth do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was hand-authored to introduce companies and authentication fields.
  """

  use Ecto.Migration

  def up do
    create table(:companies, primary_key: false) do
      add :id, :bigserial, null: false, primary_key: true
      add :name, :text, null: false
      add :company_code_hash, :bytea, null: false
      add :status, :text, null: false, default: "active"

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:companies, [:company_code_hash],
             name: "companies_unique_company_code_hash_index"
           )

    create unique_index(:companies, [:name], name: "companies_unique_name_index")

    execute("""
    INSERT INTO companies (name, company_code_hash, status, inserted_at, updated_at)
    VALUES ('Internal', decode('#{default_company_hash_hex()}', 'hex'), 'active',
      (now() AT TIME ZONE 'utc'), (now() AT TIME ZONE 'utc'))
    ON CONFLICT (name) DO NOTHING;
    """)

    rename table(:users), :name, to: :display_name

    drop_if_exists unique_index(:users, [:email], name: "users_unique_email_index")

    alter table(:users) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "users_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )

      add :login_id, :text
      add :password_hash, :text
      add :status, :text, null: false, default: "pending"
    end

    execute("""
    UPDATE users
    SET company_id = (SELECT id FROM companies WHERE name = 'Internal'),
        status = 'active'
    WHERE company_id IS NULL;
    """)

    execute("ALTER TABLE users ALTER COLUMN company_id SET NOT NULL;")

    create unique_index(:users, [:company_id, :email], name: "users_unique_company_email_index")

    create unique_index(:users, [:company_id, :login_id],
             name: "users_unique_company_login_id_index"
           )

    alter table(:tickets) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "tickets_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )

      add :visibility_scope, :text, null: false, default: "company"

      add :visibility_decided_by_id,
          references(:users,
            column: :id,
            name: "tickets_visibility_decided_by_id_fkey",
            type: :bigint,
            prefix: "public"
          )

      add :visibility_decided_at, :utc_datetime_usec
    end

    execute("""
    UPDATE tickets AS t
    SET company_id = u.company_id
    FROM users AS u
    WHERE t.requester_id = u.id AND t.company_id IS NULL;
    """)

    execute("ALTER TABLE tickets ALTER COLUMN company_id SET NOT NULL;")

    create index(:tickets, [:company_id], name: "tickets_company_id_index")

    alter table(:inquiries) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "inquiries_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    execute("""
    UPDATE inquiries AS i
    SET company_id = t.company_id
    FROM tickets AS t
    WHERE i.ticket_id = t.id AND i.company_id IS NULL;
    """)

    execute("""
    UPDATE inquiries AS i
    SET company_id = u.company_id
    FROM users AS u
    WHERE i.company_id IS NULL AND i.requester_id = u.id;
    """)

    execute("ALTER TABLE inquiries ALTER COLUMN company_id SET NOT NULL;")

    create index(:inquiries, [:company_id], name: "inquiries_company_id_index")

    alter table(:conversations) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "conversations_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    execute("""
    UPDATE conversations AS c
    SET company_id = t.company_id
    FROM tickets AS t
    WHERE c.ticket_id = t.id AND c.company_id IS NULL;
    """)

    execute("ALTER TABLE conversations ALTER COLUMN company_id SET NOT NULL;")

    create index(:conversations, [:company_id], name: "conversations_company_id_index")

    alter table(:conversation_messages) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "conversation_messages_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    execute("""
    UPDATE conversation_messages AS cm
    SET company_id = c.company_id
    FROM conversations AS c
    WHERE cm.conversation_id = c.id AND cm.company_id IS NULL;
    """)

    execute("ALTER TABLE conversation_messages ALTER COLUMN company_id SET NOT NULL;")

    create index(:conversation_messages, [:company_id],
             name: "conversation_messages_company_id_index"
           )

    alter table(:ticket_events) do
      add :company_id,
          references(:companies,
            column: :id,
            name: "ticket_events_company_id_fkey",
            type: :bigint,
            prefix: "public"
          )
    end

    execute("""
    UPDATE ticket_events AS e
    SET company_id = t.company_id
    FROM tickets AS t
    WHERE e.ticket_id = t.id AND e.company_id IS NULL;
    """)

    execute("ALTER TABLE ticket_events ALTER COLUMN company_id SET NOT NULL;")

    create index(:ticket_events, [:company_id], name: "ticket_events_company_id_index")
  end

  def down do
    drop_if_exists index(:ticket_events, [:company_id], name: "ticket_events_company_id_index")
    execute("ALTER TABLE ticket_events DROP COLUMN company_id;")

    drop_if_exists index(:conversation_messages, [:company_id],
                     name: "conversation_messages_company_id_index"
                   )

    execute("ALTER TABLE conversation_messages DROP COLUMN company_id;")

    drop_if_exists index(:conversations, [:company_id], name: "conversations_company_id_index")
    execute("ALTER TABLE conversations DROP COLUMN company_id;")

    drop_if_exists index(:inquiries, [:company_id], name: "inquiries_company_id_index")
    execute("ALTER TABLE inquiries DROP COLUMN company_id;")

    drop_if_exists index(:tickets, [:company_id], name: "tickets_company_id_index")
    execute("ALTER TABLE tickets DROP COLUMN visibility_decided_at;")
    execute("ALTER TABLE tickets DROP COLUMN visibility_decided_by_id;")
    execute("ALTER TABLE tickets DROP COLUMN visibility_scope;")
    execute("ALTER TABLE tickets DROP COLUMN company_id;")

    drop_if_exists unique_index(:users, [:company_id, :login_id],
                     name: "users_unique_company_login_id_index"
                   )

    drop_if_exists unique_index(:users, [:company_id, :email],
                     name: "users_unique_company_email_index"
                   )

    execute("ALTER TABLE users DROP COLUMN status;")
    execute("ALTER TABLE users DROP COLUMN password_hash;")
    execute("ALTER TABLE users DROP COLUMN login_id;")
    execute("ALTER TABLE users DROP COLUMN company_id;")

    create unique_index(:users, [:email], name: "users_unique_email_index")

    rename table(:users), :display_name, to: :name

    drop_if_exists unique_index(:companies, [:name], name: "companies_unique_name_index")

    drop_if_exists unique_index(:companies, [:company_code_hash],
                     name: "companies_unique_company_code_hash_index"
                   )

    drop table(:companies)
  end

  defp default_company_hash_hex do
    HelpdeskCommander.Support.CompanyCode.hash!(default_company_code())
    |> Base.encode16(case: :lower)
  end

  defp default_company_code do
    "A-000001"
  end
end
