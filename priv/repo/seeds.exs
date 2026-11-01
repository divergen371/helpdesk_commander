# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# We use Ash so seeds match the resource definitions.

require Logger

import Ash.Query

alias HelpdeskCommander.Accounts
alias HelpdeskCommander.Accounts.User
alias HelpdeskCommander.Helpdesk.Product
alias HelpdeskCommander.Support.PiiHash
company = Accounts.Auth.default_company!()

admin_email = "admin@example.com"
system_email = "system@helpdesk.local"

if User |> filter(email_hash == ^PiiHash.email(admin_email)) |> Ash.exists?(domain: Accounts) do
  :ok
else
  _user =
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "admin@example.com",
      display_name: "Admin",
      role: "admin",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)

  Logger.info("Seeded default user: admin@example.com")
end

admin_password = System.get_env("DEFAULT_ADMIN_PASSWORD")

if admin_password do
  case User |> filter(email_hash == ^PiiHash.email(admin_email)) |> Ash.read_one(domain: Accounts) do
    {:ok, %User{password_hash: nil} = admin} ->
      admin
      |> Ash.Changeset.for_update(:set_password, %{
        password: admin_password,
        password_confirmation: admin_password
      })
      |> Ash.update!(domain: Accounts)

      Logger.info("Set admin password from DEFAULT_ADMIN_PASSWORD")

    _result ->
      :ok
  end
end

if User |> filter(email_hash == ^PiiHash.email(system_email)) |> Ash.exists?(domain: Accounts) do
  :ok
else
  _system =
    User
    |> Ash.Changeset.for_create(:create, %{
      email: system_email,
      display_name: "System",
      role: "system",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)

  Logger.info("Seeded system user: #{system_email}")
end

products = Product |> filter(company_id == ^company.id) |> Ash.read!(domain: HelpdeskCommander.Helpdesk)

if products == [] do
  _product =
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Default Product",
      description: "初期登録の製品",
      company_id: company.id
    })
    |> Ash.create!(domain: HelpdeskCommander.Helpdesk)

  Logger.info("Seeded default product: Default Product")
end
