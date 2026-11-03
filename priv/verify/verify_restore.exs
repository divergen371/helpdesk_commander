defmodule HelpdeskCommander.VerifyRestore do
  @moduledoc """
  復元演習の検証スクリプト。

  `DATABASE_URL` を復元先に向けて実行する:

      DATABASE_URL=postgres://postgres:localhost:5433/helpdesk_commander_restore_drill \\
        mix run priv/verify/verify_restore.exs

  - cloak されたメール・会社名・表示名が復号できること
  - `email_hash` / `name_hash` が PII_HMAC_SECRET で計算した HMAC と一致すること

  注意: メールと会社名を標準出力に出すので、本番データでは許可された環境で実行する。
  """

  alias Ecto.Adapters.SQL
  alias HelpdeskCommander.Repo
  alias HelpdeskCommander.Support.PiiHash
  alias HelpdeskCommander.Vault

  def run do
    companies = SQL.query!(Repo, "SELECT id, encrypted_name, name_hash FROM companies ORDER BY id", [])
    users = SQL.query!(Repo, "SELECT id, encrypted_email, email_hash, encrypted_display_name FROM users ORDER BY id", [])

    IO.puts("== companies ==")

    company_results =
      Enum.map(companies.rows, fn [id, cipher, name_hash] ->
        name =
          cipher
          |> Base.decode64!()
          |> Vault.decrypt!()
          |> :erlang.binary_to_term([:safe])
          |> to_string()

        if PiiHash.company_name(name) == name_hash do
          IO.puts("  ok  id=#{id} name=#{name}")
          true
        else
          IO.puts("  NG  id=#{id} hash mismatch name=#{name}")
          false
        end
      end)

    IO.puts("== users ==")

    user_results =
      Enum.map(users.rows, fn [id, cipher, email_hash, display_name_cipher] ->
        email =
          cipher
          |> Base.decode64!()
          |> Vault.decrypt!()
          |> :erlang.binary_to_term([:safe])
          |> to_string()

        display_name =
          display_name_cipher
          |> Base.decode64!()
          |> Vault.decrypt!()
          |> :erlang.binary_to_term([:safe])
          |> to_string()

        if PiiHash.email(email) == email_hash and is_binary(display_name) do
          IO.puts("  ok  id=#{id} display_name=#{display_name} email=#{email}")
          true
        else
          IO.puts("  NG  id=#{id} hash mismatch")
          false
        end
      end)

    companies_ok = Enum.all?(company_results)
    users_ok = Enum.all?(user_results)

    IO.puts("== result ==")
    IO.puts("companies: #{length(company_results)} checked, ok=#{companies_ok}")
    IO.puts("users: #{length(user_results)} checked, ok=#{users_ok}")

    if companies_ok and users_ok do
      System.stop(0)
    else
      System.stop(1)
    end
  end
end

HelpdeskCommander.VerifyRestore.run()
