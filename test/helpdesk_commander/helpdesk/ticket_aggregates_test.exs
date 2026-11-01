defmodule HelpdeskCommander.Helpdesk.TicketAggregatesTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketVerification

  test "ticket aggregates expose verification count and latest event time" do
    user = create_user!()
    ticket = create_ticket!(user)

    assert {:ok, loaded} = Helpdesk.load_ticket_stats(ticket)
    assert loaded.verification_count == 0
    assert %DateTime{} = loaded.latest_event_at

    resolved = set_status!(ticket, "resolved", user.id)

    assert {:ok, _verification} =
             TicketVerification
             |> Ash.Changeset.for_create(:create, %{
               ticket_id: resolved.id,
               verifier_id: user.id,
               result: "passed"
             })
             |> Ash.create(domain: Helpdesk)

    assert {:ok, loaded} = Helpdesk.load_ticket_stats(resolved)
    assert loaded.verification_count == 1
    assert DateTime.compare(loaded.latest_event_at, ticket.inserted_at) in [:gt, :eq]
  end

  defp set_status!(ticket, status, actor_id) do
    ticket
    |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: actor_id})
    |> Ash.update!(domain: Helpdesk)
  end

  defp create_user! do
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "aggregate+#{System.unique_integer([:positive])}@example.com",
      display_name: "Aggregate User",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(user) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Aggregate Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Aggregate Ticket",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
