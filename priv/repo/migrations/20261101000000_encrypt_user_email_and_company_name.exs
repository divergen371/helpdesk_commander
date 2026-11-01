defmodule HelpdeskCommander.Repo.Migrations.EncryptUserEmailAndCompanyName do
  use Ecto.Migration

  @email_index "users_unique_company_email_index"
  @name_index "companies_unique_name_index"

  def up do
    alter table(:users) do
      add :encrypted_email, :binary
      add :email_hash, :binary
    end

    alter table(:companies) do
      add :encrypted_name, :binary
      add :name_hash, :binary
    end

    flush()

    backfill_users()
    backfill_companies()

    alter table(:users) do
      modify :encrypted_email, :binary, null: false
      modify :email_hash, :binary, null: false
    end

    alter table(:companies) do
      modify :encrypted_name, :binary, null: false
      modify :name_hash, :binary, null: false
    end

    drop unique_index(:users, [:company_id, :email], name: @email_index)
    drop unique_index(:companies, [:name], name: @name_index)

    create unique_index(:users, [:company_id, :email_hash],
             name: "users_unique_company_email_hash_index"
           )

    create unique_index(:companies, [:name_hash], name: "companies_unique_name_hash_index")

    alter table(:users) do
      remove :email
    end

    alter table(:companies) do
      remove :name
    end
  end

  def down do
    alter table(:users) do
      add :email, :string
    end

    alter table(:companies) do
      add :name, :string
    end

    flush()

    decrypt_users()
    decrypt_companies()

    alter table(:users) do
      modify :email, :string, null: false
    end

    alter table(:companies) do
      modify :name, :string, null: false
    end

    drop unique_index(:users, [:company_id, :email_hash],
           name: "users_unique_company_email_hash_index"
         )

    drop unique_index(:companies, [:name_hash], name: "companies_unique_name_hash_index")

    create unique_index(:users, [:company_id, :email], name: @email_index)
    create unique_index(:companies, [:name], name: @name_index)

    alter table(:users) do
      remove :encrypted_email
      remove :email_hash
    end

    alter table(:companies) do
      remove :encrypted_name
      remove :name_hash
    end
  end

  defp backfill_users do
    with_vault(fn ->
      for [id, email] <- rows("SELECT id, email FROM users") do
        normalized = email |> String.trim() |> String.downcase()

        repo().query!(
          "UPDATE users SET encrypted_email = $1, email_hash = $2 WHERE id = $3",
          [encrypt(normalized), email_hash(normalized), id]
        )
      end
    end)
  end

  defp backfill_companies do
    with_vault(fn ->
      for [id, name] <- rows("SELECT id, name FROM companies") do
        normalized = String.trim(name)

        repo().query!(
          "UPDATE companies SET encrypted_name = $1, name_hash = $2 WHERE id = $3",
          [encrypt(normalized), company_name_hash(normalized), id]
        )
      end
    end)
  end

  defp decrypt_users do
    with_vault(fn ->
      for [id, encrypted] <- rows("SELECT id, encrypted_email FROM users") do
        repo().query!("UPDATE users SET email = $1 WHERE id = $2", [decrypt(encrypted), id])
      end
    end)
  end

  defp decrypt_companies do
    with_vault(fn ->
      for [id, encrypted] <- rows("SELECT id, encrypted_name FROM companies") do
        repo().query!("UPDATE companies SET name = $1 WHERE id = $2", [decrypt(encrypted), id])
      end
    end)
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

  defp decrypt(nil), do: nil

  defp decrypt(value) do
    value
    |> Base.decode64!()
    |> HelpdeskCommander.Vault.decrypt!()
    |> :erlang.binary_to_term()
  end

  defp email_hash(normalized) do
    :crypto.mac(:hmac, :sha256, pii_secret(), normalized)
  end

  defp company_name_hash(normalized) do
    :crypto.mac(:hmac, :sha256, pii_secret(), normalized)
  end

  defp pii_secret do
    Application.fetch_env!(:helpdesk_commander, :pii_hmac_secret)
  end
end
