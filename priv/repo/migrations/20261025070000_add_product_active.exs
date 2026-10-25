defmodule HelpdeskCommander.Repo.Migrations.AddProductActive do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :active, :boolean, null: false, default: true
    end

    create index(:products, [:company_id, :active])
  end
end
