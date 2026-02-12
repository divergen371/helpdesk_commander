defmodule HelpdeskCommander.Repo.Migrations.AddUserSuspensionFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :suspended_at, :utc_datetime_usec
      add :anonymized_at, :utc_datetime_usec
    end

    create index(:users, [:status])
    create index(:users, [:suspended_at], where: "status = 'suspended'")
  end
end
