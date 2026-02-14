defmodule HelpdeskCommander.Repo.Migrations.AddTicketNotifications do
  use Ecto.Migration

  def change do
    create table(:ticket_notifications, primary_key: false) do
      add :id, :bigserial, null: false, primary_key: true
      add :notification_type, :text, null: false
      add :title, :text, null: false
      add :body, :text, null: false
      add :meta, :map, null: false, default: %{}
      add :read_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :company_id,
          references(:companies, type: :bigint, on_delete: :nothing),
          null: false

      add :ticket_id,
          references(:tickets, type: :bigint, on_delete: :delete_all),
          null: false

      add :recipient_id,
          references(:users, type: :bigint, on_delete: :delete_all),
          null: false

      add :actor_id,
          references(:users, type: :bigint, on_delete: :nilify_all)
    end

    create index(:ticket_notifications, [:recipient_id, :inserted_at],
             name: "ticket_notifications_recipient_id_inserted_at_index"
           )

    create index(:ticket_notifications, [:recipient_id, :read_at],
             name: "ticket_notifications_recipient_id_read_at_index"
           )

    create index(:ticket_notifications, [:ticket_id],
             name: "ticket_notifications_ticket_id_index"
           )

    create index(:ticket_notifications, [:company_id],
             name: "ticket_notifications_company_id_index"
           )
  end
end
