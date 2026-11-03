defmodule HelpdeskCommander.Helpdesk.GlobalPublicationTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent

  setup do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    product = create_product!(company)
    ticket = create_ticket!(product, admin, "p1")

    %{company: company, admin: admin, product: product, ticket: ticket}
  end

  test "P1 with an active SEV1 incident becomes a global publication candidate", %{
    ticket: ticket,
    admin: admin
  } do
    assert {:ok, incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    assert incident.severity == "sev1"

    reloaded = get_ticket!(ticket)
    assert reloaded.visibility_scope == "global_pending"
    assert event_count(ticket.id, "global_publication_candidate") == 1
  end

  test "P1 with a lower severity stays company-scoped", %{ticket: ticket, admin: admin} do
    assert {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev2"}, admin)

    assert get_ticket!(ticket).visibility_scope == "company"
  end

  test "a non-P1 ticket with SEV1 stays company-scoped", %{
    company: company,
    admin: admin,
    product: product
  } do
    ticket = create_ticket!(product, admin, "p2")

    assert {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)

    assert get_ticket!(ticket).visibility_scope == "company"
    assert get_ticket!(ticket).company_id == company.id
  end

  test "an admin approves the candidate and records the decision", %{
    ticket: ticket,
    admin: admin
  } do
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    candidate = get_ticket!(ticket)

    assert {:ok, approved} = Helpdesk.approve_global_publication(candidate, admin)
    assert approved.visibility_scope == "global"
    assert approved.visibility_decided_by_id == admin.id
    assert approved.visibility_decided_at != nil
    assert event_count(ticket.id, "global_publication_approved") == 1

    # 承認済みの公開は、SEV が下がっても維持する。
    {:ok, incident} = Helpdesk.get_incident(ticket.id, tenant: ticket.company_id)
    {:ok, _updated} = Helpdesk.update_incident(incident, %{"severity" => "sev3"}, admin)
    assert get_ticket!(ticket).visibility_scope == "global"

    inc = Ash.get!(HelpdeskCommander.Helpdesk.Incident, incident.id, domain: Helpdesk)
    {:ok, _demoted} = Helpdesk.demote_incident(inc, admin)
    assert get_ticket!(ticket).visibility_scope == "global"
  end

  test "an admin rejects the candidate and returns it to company scope", %{
    ticket: ticket,
    admin: admin
  } do
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    candidate = get_ticket!(ticket)

    assert {:ok, rejected} = Helpdesk.reject_global_publication(candidate, admin)
    assert rejected.visibility_scope == "company"
    assert rejected.visibility_decided_by_id == admin.id
    assert rejected.visibility_decided_at != nil
    assert event_count(ticket.id, "global_publication_rejected") == 1
  end

  test "demoting or lowering the incident withdraws a pending candidate", %{
    ticket: ticket,
    admin: admin
  } do
    {:ok, incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    assert get_ticket!(ticket).visibility_scope == "global_pending"

    {:ok, lowered} = Helpdesk.update_incident(incident, %{"severity" => "sev2"}, admin)
    assert get_ticket!(ticket).visibility_scope == "company"
    assert event_count(ticket.id, "global_publication_withdrawn") == 1

    {:ok, again} = Helpdesk.update_incident(lowered, %{"severity" => "sev1"}, admin)
    assert get_ticket!(ticket).visibility_scope == "global_pending"

    {:ok, demoted} = Helpdesk.demote_incident(again, admin)
    assert demoted.demoted_at != nil
    assert get_ticket!(ticket).visibility_scope == "company"
    assert event_count(ticket.id, "global_publication_withdrawn") == 2
  end

  test "changing the ticket to P1 after promotion creates the candidate", %{
    product: product,
    admin: admin
  } do
    ticket = create_ticket!(product, admin, "p2")
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    assert get_ticket!(ticket).visibility_scope == "company"

    assert {:ok, updated} =
             Helpdesk.update_ticket(ticket, %{"priority" => "p1"}, actor: admin)

    assert updated.visibility_scope == "global_pending"
  end

  test "non-privileged users cannot approve or reject", %{ticket: ticket, admin: admin} do
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev1"}, admin)
    user = create_user!(ticket.company_id, "user")
    candidate = get_ticket!(ticket)

    assert {:error, :forbidden} = Helpdesk.approve_global_publication(candidate, user)
    assert {:error, :forbidden} = Helpdesk.reject_global_publication(candidate, user)
  end

  test "approving a non-candidate returns not_pending", %{ticket: ticket, admin: admin} do
    assert {:error, :not_pending} = Helpdesk.approve_global_publication(ticket, admin)
  end

  defp get_ticket!(ticket) do
    Ash.get!(Ticket, ticket.id, domain: Helpdesk, tenant: ticket.company_id)
  end

  defp event_count(ticket_id, event_type) do
    TicketEvent
    |> filter(ticket_id == ^ticket_id and event_type == ^event_type)
    |> Ash.read!(domain: Helpdesk)
    |> length()
  end

  defp create_ticket!(product, requester, priority) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Global publication #{priority}",
      priority: priority,
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Global Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "global+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Global #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Global Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
