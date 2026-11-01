defmodule HelpdeskCommander.Repo.Migrations.AddConversationMessageMetadata do
  use Ecto.Migration

  def change do
    alter table(:conversation_messages) do
      add :edited_at, :utc_datetime_usec
    end

    create index(:conversation_messages, [:conversation_id, :deleted_at])
  end
end
