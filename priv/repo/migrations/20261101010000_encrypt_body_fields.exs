defmodule HelpdeskCommander.Repo.Migrations.EncryptBodyFields do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :encrypted_display_name, :binary
    end

    alter table(:tickets) do
      add :encrypted_description, :binary
    end

    alter table(:inquiries) do
      add :encrypted_body, :binary
    end

    alter table(:conversation_messages) do
      add :encrypted_body, :binary
    end

    flush()

    with_vault(fn ->
      backfill("users", "display_name", "encrypted_display_name")
      backfill("tickets", "description", "encrypted_description")
      backfill("inquiries", "body", "encrypted_body")
      backfill("conversation_messages", "body", "encrypted_body")
    end)

    alter table(:users) do
      modify :encrypted_display_name, :binary, null: false
    end

    alter table(:inquiries) do
      modify :encrypted_body, :binary, null: false
    end

    alter table(:conversation_messages) do
      modify :encrypted_body, :binary, null: false
    end

    alter table(:users) do
      remove :display_name
    end

    alter table(:tickets) do
      remove :description
    end

    alter table(:inquiries) do
      remove :body
    end

    alter table(:conversation_messages) do
      remove :body
    end
  end

  def down do
    alter table(:users) do
      add :display_name, :text
    end

    alter table(:tickets) do
      add :description, :text
    end

    alter table(:inquiries) do
      add :body, :text
    end

    alter table(:conversation_messages) do
      add :body, :text
    end

    flush()

    with_vault(fn ->
      restore("users", "encrypted_display_name", "display_name")
      restore("tickets", "encrypted_description", "description")
      restore("inquiries", "encrypted_body", "body")
      restore("conversation_messages", "encrypted_body", "body")
    end)

    alter table(:users) do
      modify :display_name, :text, null: false
    end

    alter table(:inquiries) do
      modify :body, :text, null: false
    end

    alter table(:conversation_messages) do
      modify :body, :text, null: false
    end

    alter table(:users) do
      remove :encrypted_display_name
    end

    alter table(:tickets) do
      remove :encrypted_description
    end

    alter table(:inquiries) do
      remove :encrypted_body
    end

    alter table(:conversation_messages) do
      remove :encrypted_body
    end
  end

  defp backfill(table, plain_column, encrypted_column) do
    for [id, value] <- rows("SELECT id, #{plain_column} FROM #{table}") do
      if value do
        repo().query!(
          "UPDATE #{table} SET #{encrypted_column} = $1 WHERE id = $2",
          [encrypt(value), id]
        )
      end
    end
  end

  defp restore(table, encrypted_column, plain_column) do
    for [id, value] <- rows("SELECT id, #{encrypted_column} FROM #{table}") do
      if value do
        repo().query!(
          "UPDATE #{table} SET #{plain_column} = $1 WHERE id = $2",
          [decrypt(value), id]
        )
      end
    end
  end

  defp rows(sql) do
    repo().query!(sql, [], log: false).rows
  end

  # Mirrors AshCloak's storage format: term_to_binary then Base64.
  defp encrypt(value) do
    value
    |> :erlang.term_to_binary()
    |> HelpdeskCommander.Vault.encrypt!()
    |> Base.encode64()
  end

  defp decrypt(value) do
    value
    |> Base.decode64!()
    |> HelpdeskCommander.Vault.decrypt!()
    |> :erlang.binary_to_term()
  end

  # Migrations may run before the application starts, so start the vault only
  # for the duration of the backfill to avoid clashing with supervision.
  defp with_vault(fun) do
    started? = is_nil(Process.whereis(HelpdeskCommander.Vault))

    if started? do
      {:ok, _pid} = HelpdeskCommander.Vault.start_link()
    end

    try do
      fun.()
    after
      if started?, do: GenServer.stop(HelpdeskCommander.Vault)
    end
  end
end
