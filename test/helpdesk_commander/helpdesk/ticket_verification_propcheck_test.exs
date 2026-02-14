defmodule HelpdeskCommander.Helpdesk.TicketVerificationPropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketVerification

  property "propcheck: invalid verification results are rejected" do
    forall suffix <- utf8() do
      user = create_user!()
      ticket = create_ticket!(user) |> resolve_ticket!(user)
      invalid = "invalid_" <> String.slice(suffix, 0, 12)

      assert {:error, _error} =
               TicketVerification
               |> Ash.Changeset.for_create(:create, %{
                 ticket_id: ticket.id,
                 verifier_id: user.id,
                 result: invalid,
                 notes: "propcheck invalid"
               })
               |> Ash.create(domain: Helpdesk)

      true
    end
  end

  property "propcheck: valid verification results set verified_at" do
    forall result <- elements(["passed", "failed", "needs_review"]) do
      user = create_user!()
      ticket = create_ticket!(user) |> resolve_ticket!(user)

      assert {:ok, verification} =
               TicketVerification
               |> Ash.Changeset.for_create(:create, %{
                 ticket_id: ticket.id,
                 verifier_id: user.id,
                 result: result,
                 notes: "propcheck ok"
               })
               |> Ash.create(domain: Helpdesk)

      assert verification.verified_at != nil
      true
    end
  end

  property "propcheck: verification is rejected before resolved status", numtests: 10 do
    forall status <- elements(["new", "triage", "in_progress", "waiting", "verified", "closed"]) do
      {user, admin} = create_users!()
      ticket = create_ticket!(user)
      ticket = ensure_status!(ticket, status, user, admin)

      assert {:error, _error} =
               TicketVerification
               |> Ash.Changeset.for_create(:create, %{
                 ticket_id: ticket.id,
                 verifier_id: user.id,
                 result: "passed",
                 notes: "propcheck not resolved"
               })
               |> Ash.create(domain: Helpdesk)

      true
    end
  end

  defp resolve_ticket!(%Ticket{} = ticket, %User{} = user) do
    ticket
    |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
    |> Ash.update!(domain: Helpdesk)
  end

  defp create_user! do
    email = "verify+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Verify User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_users! do
    company = Accounts.Auth.default_company!()
    user = create_user_for_company!(company.id, "user")
    admin = create_user_for_company!(company.id, "admin")
    {user, admin}
  end

  defp create_user_for_company!(company_id, role) do
    email = "verify+#{role}+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Verify #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Verification Test",
      description: "Verification Test",
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

  defp ensure_status!(%Ticket{} = ticket, "new", _user, _admin), do: ticket

  defp ensure_status!(%Ticket{} = ticket, "triage", %User{} = user, _admin) do
    set_status!(ticket, "triage", user.id)
  end

  defp ensure_status!(%Ticket{} = ticket, "in_progress", %User{} = user, _admin) do
    set_status!(ticket, "in_progress", user.id)
  end

  defp ensure_status!(%Ticket{} = ticket, "waiting", %User{} = user, _admin) do
    set_status!(ticket, "waiting", user.id)
  end

  defp ensure_status!(%Ticket{} = ticket, "verified", %User{} = user, %User{} = admin) do
    ticket
    |> set_status!("resolved", user.id)
    |> set_status!("verified", admin.id)
  end

  defp ensure_status!(%Ticket{} = ticket, "closed", %User{} = user, %User{} = admin) do
    ticket
    |> set_status!("resolved", user.id)
    |> set_status!("closed", admin.id)
  end

  defp set_status!(%Ticket{} = ticket, status, actor_id) do
    ticket
    |> Ash.Changeset.for_update(:set_status, %{status: status, actor_id: actor_id})
    |> Ash.update!(domain: Helpdesk)
  end
end
