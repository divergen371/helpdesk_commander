defmodule HelpdeskCommander.Helpdesk.IncidentTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Incident
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent

  test "promotes a ticket with severity and impact details" do
    {ticket, admin} = create_ticket_with_admin!()

    assert {:ok, incident} =
             Helpdesk.promote_incident(
               ticket,
               %{
                 "severity" => "sev1",
                 "impact_scope" => "全社",
                 "announcement" => "一次対応中"
               },
               admin
             )

    assert incident.severity == "sev1"
    assert incident.impact_scope == "全社"
    assert incident.announcement == "一次対応中"
    assert incident.demoted_at == nil

    assert incident_event_count(ticket.id, "incident_promoted", admin) == 1
  end

  test "rejects promotion by a non-privileged user" do
    {ticket, _admin} = create_ticket_with_admin!()
    user = create_user!(ticket.company_id, "user")

    assert {:error, :forbidden} =
             Helpdesk.promote_incident(ticket, %{"severity" => "sev2"}, user)
  end

  test "updates and demotes an incident with audit events" do
    {ticket, admin} = create_ticket_with_admin!()
    {:ok, incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev2"}, admin)

    assert {:ok, updated} =
             Helpdesk.update_incident(incident, %{"severity" => "sev1"}, admin)

    assert updated.severity == "sev1"

    assert {:ok, demoted} = Helpdesk.demote_incident(updated, admin)
    assert demoted.demoted_at != nil
    assert incident_event_count(ticket.id, "incident_demoted", admin) == 1

    assert {:ok, reactivated} =
             Helpdesk.promote_incident(
               ticket,
               %{"severity" => "sev4", "impact_scope" => "一部"},
               admin
             )

    assert reactivated.demoted_at == nil
    assert reactivated.severity == "sev4"
  end

  test "records timeline phases and rejects unknown phases" do
    {ticket, admin} = create_ticket_with_admin!()
    {:ok, incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev3"}, admin)

    assert {:ok, event} =
             Helpdesk.add_incident_event(
               incident,
               %{"phase" => "recovery", "body" => "復旧作業を完了"},
               admin
             )

    assert event.phase == "recovery"

    assert {:error, _error} =
             Helpdesk.add_incident_event(
               incident,
               %{"phase" => "unknown", "body" => "不正"},
               admin
             )

    assert {:ok, [loaded]} = Helpdesk.list_incident_events(incident.id, tenant: ticket.company_id)
    assert loaded.id == event.id
    assert incident_event_count(ticket.id, "incident_timeline_updated", admin) == 1
  end

  test "incident reads are isolated by tenant" do
    {ticket, admin} = create_ticket_with_admin!()
    {:ok, _incident} = Helpdesk.promote_incident(ticket, %{"severity" => "sev2"}, admin)

    other_company = create_company!()

    assert {:ok, []} =
             Incident
             |> filter(ticket_id == ^ticket.id)
             |> Ash.read(domain: Helpdesk, tenant: other_company.id)
  end

  defp incident_event_count(ticket_id, event_type, actor) do
    TicketEvent
    |> filter(ticket_id == ^ticket_id and event_type == ^event_type)
    |> Ash.read!(domain: Helpdesk, actor: actor)
    |> length()
  end

  defp create_ticket_with_admin! do
    company = create_company!()
    admin = create_user!(company.id, "admin")
    user = create_user!(company.id, "user")
    product = create_product!(company)

    ticket =
      Ticket
      |> Ash.Changeset.for_create(:create, %{
        subject: "Incident ticket",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    {ticket, admin}
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Incident Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "incident+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Incident #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Incident Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
