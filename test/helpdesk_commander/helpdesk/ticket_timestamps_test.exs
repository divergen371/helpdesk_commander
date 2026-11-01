defmodule HelpdeskCommander.Helpdesk.TicketTimestampsTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketVerification

  test "set_status fills the timestamp of the target status" do
    user = create_user!("user")
    admin = create_user!("admin")
    ticket = create_ticket!(user)

    resolved = set_status!(ticket, "resolved", user.id)
    assert resolved.resolved_at != nil
    assert resolved.verified_at == nil

    verified = set_status!(resolved, "verified", admin.id)
    assert verified.verified_at != nil
    assert verified.resolved_at == resolved.resolved_at
  end

  test "set_status keeps timestamps that are already recorded" do
    user = create_user!("user")
    ticket = create_ticket!(user)

    resolved = set_status!(ticket, "resolved", user.id)
    reopened = set_status!(resolved, "in_progress", user.id)
    reresolved = set_status!(reopened, "resolved", user.id)

    assert reresolved.resolved_at == resolved.resolved_at
  end

  test "verification is rejected for tickets that are not resolved" do
    user = create_user!("user")
    ticket = create_ticket!(user)

    assert {:error, error} =
             TicketVerification
             |> Ash.Changeset.for_create(:create, %{
               ticket_id: ticket.id,
               verifier_id: user.id,
               result: "passed"
             })
             |> Ash.create(domain: Helpdesk)

    assert Exception.message(error) =~ "resolved以外のチケットは検証できません"
  end

  test "verification keeps an explicitly provided verified_at" do
    user = create_user!("user")
    ticket = create_ticket!(user) |> set_status!("resolved", user.id)
    verified_at = ~U[2026-01-02 03:04:05.000000Z]

    assert {:ok, verification} =
             TicketVerification
             |> Ash.Changeset.for_create(:create, %{
               ticket_id: ticket.id,
               verifier_id: user.id,
               result: "passed",
               verified_at: verified_at
             })
             |> Ash.create(domain: Helpdesk)

    assert verification.verified_at == verified_at
  end

  defp set_status!(%Ticket{} = ticket, status, actor_id) do
    ticket
    |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: actor_id})
    |> Ash.update!(domain: Helpdesk)
  end

  defp create_user!(role) do
    company = Accounts.Auth.default_company!()
    email = "timestamps+#{role}+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Timestamps #{role}",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Timestamp Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Timestamp Test",
      description: "Timestamp Test",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
