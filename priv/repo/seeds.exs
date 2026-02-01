# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# We use Ash so seeds match the resource definitions.

require Logger

alias HelpdeskCommander.Accounts
alias HelpdeskCommander.Accounts.User

users = Ash.read!(User, domain: Accounts)

if users == [] do
  _user =
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "admin@example.com",
      name: "Admin",
      role: "admin"
    })
    |> Ash.create!(domain: Accounts)

  Logger.info("Seeded default user: admin@example.com")
end
