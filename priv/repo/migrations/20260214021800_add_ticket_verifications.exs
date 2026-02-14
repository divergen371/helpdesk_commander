defmodule HelpdeskCommander.Repo.Migrations.AddTicketVerifications do
  use Ecto.Migration

  def change do
    create table(:ticket_verifications, primary_key: false) do
      add :id, :bigserial, null: false, primary_key: true
      add :result, :text, null: false
      add :notes, :text

      add :verified_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :company_id,
          references(:companies, type: :bigint, on_delete: :nothing),
          null: false

      add :ticket_id,
          references(:tickets, type: :bigint, on_delete: :delete_all),
          null: false

      add :verifier_id,
          references(:users, type: :bigint, on_delete: :nothing),
          null: false
    end

    create index(:ticket_verifications, [:ticket_id, :id],
             name: "ticket_verifications_ticket_id_id_index"
           )

    create index(:ticket_verifications, [:company_id],
             name: "ticket_verifications_company_id_index"
           )

    create index(:ticket_verifications, [:verifier_id],
             name: "ticket_verifications_verifier_id_index"
           )
  end
end
