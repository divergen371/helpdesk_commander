defmodule HelpdeskCommander.Helpdesk.TicketAuthorizationTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "non-admin cannot set verified/closed" do
    user = create_user!()
    ticket = create_ticket!(user)

    resolved =
      ticket
      |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
      |> Ash.update!(domain: Helpdesk)

    assert {:error, _error} =
             resolved
             |> Ash.Changeset.for_update(:set_status, %{status: "verified", actor_id: user.id})
             |> Ash.update(domain: Helpdesk)
  end

  test "admin can set verified/closed" do
    user = create_user!()
    admin = create_user!("admin")
    ticket = create_ticket!(user)

    resolved =
      ticket
      |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
      |> Ash.update!(domain: Helpdesk)

    verified =
      resolved
      |> Ash.Changeset.for_update(:set_status, %{status: "verified", actor_id: admin.id})
      |> Ash.update!(domain: Helpdesk)

    assert verified.status == "verified"
  end

  test "priority update requires privileged actor" do
    user = create_user!()
    admin = create_user!("leader")
    ticket = create_ticket!(user)

    assert {:error, _error} =
             ticket
             |> Ash.Changeset.for_update(:update, %{priority: "p1", actor_id: user.id})
             |> Ash.update(domain: Helpdesk)

    updated =
      ticket
      |> Ash.Changeset.for_update(:update, %{priority: "p1", actor_id: admin.id})
      |> Ash.update!(domain: Helpdesk)

    assert updated.priority == "p1"
  end

  test "non-privileged update path still works without actor_id" do
    user = create_user!()
    ticket = create_ticket!(user)
    now = DateTime.utc_now()

    updated =
      ticket
      |> Ash.Changeset.for_update(:update, %{latest_message_at: now})
      |> Ash.update!(domain: Helpdesk)

    assert DateTime.compare(updated.latest_message_at, now) in [:eq, :gt]
  end

  defp create_user!(role \\ "user") do
    email = "test+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Test ticket",
      description: "Test",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
