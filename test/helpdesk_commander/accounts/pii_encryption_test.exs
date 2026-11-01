defmodule HelpdeskCommander.Accounts.PiiEncryptionTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Repo
  alias HelpdeskCommander.Support.PiiHash

  test "email is encrypted at rest and readable through the resource" do
    company = create_company!()
    user = create_user!(company, "plain@example.com")

    assert user.email == "plain@example.com"
    assert user.email_hash == PiiHash.email("plain@example.com")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_email FROM users WHERE id = $1", [user.id])

    refute stored =~ "plain@example.com"

    assert HelpdeskCommander.Vault.decrypt!(Base.decode64!(stored)) ==
             :erlang.term_to_binary("plain@example.com")
  end

  test "company name is encrypted at rest and readable through the resource" do
    company = create_company!("Encrypted Co")

    assert company.name == "Encrypted Co"
    assert company.name_hash == PiiHash.company_name("Encrypted Co")

    %{rows: [[stored]]} =
      Repo.query!("SELECT encrypted_name FROM companies WHERE id = $1", [company.id])

    refute stored =~ "Encrypted Co"
  end

  test "email uniqueness uses the hash within a company" do
    company = create_company!()
    create_user!(company, "dup@example.com")

    assert {:error, _error} = create_user(company, "DUP@example.com")

    other_company = create_company!()
    assert {:ok, _user} = create_user(other_company, "dup@example.com")
  end

  test "company name uniqueness uses the hash" do
    _company = create_company!("Unique Co")

    assert {:error, _error} =
             Company
             |> Ash.Changeset.for_create(:create, %{
               name: " Unique Co ",
               company_code: unique_company_code()
             })
             |> Ash.create(domain: Accounts)
  end

  test "anonymize replaces the email and keeps the hash consistent" do
    company = create_company!()
    user = create_user!(company, "removed@example.com")

    anonymized =
      user
      |> Ash.Changeset.for_update(:anonymize, %{})
      |> Ash.update!(domain: Accounts)

    assert anonymized.email == "deleted-#{user.id}@anonymized.local"
    assert anonymized.email_hash == PiiHash.email(anonymized.email)
  end

  defp create_user!(company, email) do
    {:ok, user} = create_user(company, email)
    user
  end

  defp create_user(company, email) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: email,
      status: "active",
      company_id: company.id
    })
    |> Ash.create(domain: Accounts)
  end

  defp create_company!(name \\ nil) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: name || "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
