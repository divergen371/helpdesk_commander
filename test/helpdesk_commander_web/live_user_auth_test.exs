defmodule HelpdeskCommanderWeb.LiveUserAuthTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommanderWeb.LiveUserAuth

  test "live_user_required halts when session is empty" do
    socket =
      %Phoenix.LiveView.Socket{
        endpoint: HelpdeskCommanderWeb.Endpoint,
        assigns: %{flash: %{}, __changed__: %{}}
      }

    assert {:halt, _socket} = LiveUserAuth.on_mount(:live_user_required, %{}, %{}, socket)
  end

  test "admin_required halts for non-admin user" do
    company = create_company!()
    user = create_user!(company, role: "user", status: "active")

    socket =
      %Phoenix.LiveView.Socket{
        endpoint: HelpdeskCommanderWeb.Endpoint,
        assigns: %{flash: %{}, __changed__: %{}}
      }

    assert {:halt, _socket} = LiveUserAuth.on_mount(:admin_required, %{}, %{"user_id" => user.id}, socket)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(%Company{id: company_id}, opts) do
    email = Keyword.get(opts, :email, "user+#{System.unique_integer([:positive])}@example.com")
    status = Keyword.get(opts, :status, "active")
    role = Keyword.get(opts, :role, "user")

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      role: role,
      status: status,
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp unique_company_code do
    suffix =
      System.unique_integer([:positive])
      |> rem(900_000)
      |> Kernel.+(100_000)
      |> Integer.to_string()

    "A-#{suffix}"
  end
end
