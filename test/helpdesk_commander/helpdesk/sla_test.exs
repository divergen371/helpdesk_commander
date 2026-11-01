defmodule HelpdeskCommander.Helpdesk.SlaTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.IncidentEvent
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Sla
  alias HelpdeskCommander.Helpdesk.Ticket

  describe "defaults" do
    test "orders targets from p1 to p4" do
      assert Sla.default_targets("p1") == %{
               first_response: 15,
               mitigation: 60,
               resolution: 240,
               restoration: 480
             }

      assert Sla.default_targets("p4").resolution == 8_640
      assert Sla.default_targets("unknown") == nil
    end
  end

  describe "evaluate/4" do
    setup do
      now = DateTime.utc_now()
      start = DateTime.add(now, -60 * 60, :second)
      %{now: now, start: start}
    end

    test "marks an unanswered first response as breached after the target", %{now: now, start: start} do
      ticket = %Ticket{inserted_at: start, first_response_at: nil, resolved_at: nil}

      result =
        Sla.evaluate(
          ticket,
          %{first_response: 30, mitigation: 60, resolution: 240, restoration: 480},
          %{incident: nil, events: []},
          now
        )

      first_response = Enum.find(result.metrics, &(&1.key == :first_response))
      assert first_response.status == :breached
      assert first_response.elapsed_minutes == 60

      assert result.metrics
             |> Enum.filter(&(&1.key in [:mitigation, :restoration]))
             |> Enum.all?(&(&1.status == :not_applicable))
    end

    test "marks a response within the target as met", %{now: now, start: start} do
      ticket = %Ticket{
        inserted_at: start,
        first_response_at: DateTime.add(start, 10 * 60, :second),
        resolved_at: nil
      }

      result =
        Sla.evaluate(
          ticket,
          %{first_response: 30, mitigation: 60, resolution: 240, restoration: 480},
          %{incident: nil, events: []},
          now
        )

      first_response = Enum.find(result.metrics, &(&1.key == :first_response))
      assert first_response.status == :met
      assert first_response.elapsed_minutes == 10
    end

    test "marks a late resolution as breached", %{now: now, start: start} do
      ticket = %Ticket{
        inserted_at: start,
        first_response_at: DateTime.add(start, 5 * 60, :second),
        resolved_at: DateTime.add(start, 50 * 60, :second)
      }

      result =
        Sla.evaluate(
          ticket,
          %{first_response: 30, mitigation: 60, resolution: 45, restoration: 480},
          %{incident: nil, events: []},
          now
        )

      resolution = Enum.find(result.metrics, &(&1.key == :resolution))
      assert resolution.status == :breached
      assert resolution.elapsed_minutes == 50
    end

    test "uses incident timeline for mitigation and restoration", %{now: now, start: start} do
      ticket = %Ticket{inserted_at: start, first_response_at: nil, resolved_at: nil}
      incident = %{id: 1}

      events = [
        %IncidentEvent{
          incident_id: 1,
          phase: "mitigation",
          inserted_at: DateTime.add(start, 20 * 60, :second)
        },
        %IncidentEvent{
          incident_id: 1,
          phase: "recovery",
          inserted_at: DateTime.add(start, 3 * 60 * 60, :second)
        }
      ]

      result =
        Sla.evaluate(
          ticket,
          %{first_response: 30, mitigation: 60, resolution: 240, restoration: 120},
          %{incident: incident, events: events},
          now
        )

      mitigation = Enum.find(result.metrics, &(&1.key == :mitigation))
      restoration = Enum.find(result.metrics, &(&1.key == :restoration))

      assert mitigation.status == :met
      assert restoration.status == :breached
    end
  end

  describe "policies" do
    test "saves and reads a policy per company and priority" do
      company = create_company!()
      admin = create_user!(company.id, "admin")

      assert {:ok, policy} =
               Sla.save_policy(
                 company.id,
                 "p1",
                 %{
                   "first_response_minutes" => "10",
                   "mitigation_minutes" => "30",
                   "resolution_minutes" => "120",
                   "restoration_minutes" => "240"
                 },
                 admin
               )

      assert policy.first_response_minutes == 10

      assert {:ok, targets} = Sla.get_targets(company.id, "p1")
      assert targets == %{first_response: 10, mitigation: 30, resolution: 120, restoration: 240}

      assert {:ok, rows} = Sla.list_targets(company.id)
      p1 = Enum.find(rows, &(&1.priority == "p1"))
      p2 = Enum.find(rows, &(&1.priority == "p2"))
      assert p1.source == :configured
      assert p2.source == :default

      other_company = create_company!()
      assert {:ok, other_targets} = Sla.get_targets(other_company.id, "p1")
      assert other_targets.first_response == 15
    end

    test "rejects policy changes from non-privileged users" do
      company = create_company!()
      user = create_user!(company.id, "user")

      assert {:error, :forbidden} =
               Sla.save_policy(
                 company.id,
                 "p1",
                 %{
                   "first_response_minutes" => "10",
                   "mitigation_minutes" => "30",
                   "resolution_minutes" => "120",
                   "restoration_minutes" => "240"
                 },
                 user
               )
    end
  end

  describe "breached_tickets/3" do
    test "returns open tickets that passed a target" do
      company = create_company!()
      admin = create_user!(company.id, "admin")
      product = create_product!(company)
      ticket = create_ticket!(product, admin)

      old = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)

      ticket
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:inserted_at, old)
      |> Ash.update!(domain: Helpdesk, tenant: company.id)

      assert {:ok, [breach]} = Sla.breached_tickets(company.id)
      assert breach.ticket.id == ticket.id
      assert breach.breached?
      assert Enum.any?(breach.metrics, &(&1.key == :first_response and &1.status == :breached))

      assert {:ok, 1} = Sla.breach_count(company.id)
    end

    test "excludes closed tickets and other companies" do
      company = create_company!()
      admin = create_user!(company.id, "admin")
      product = create_product!(company)
      ticket = create_ticket!(product, admin)

      old = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)

      ticket
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:inserted_at, old)
      |> Ash.Changeset.force_change_attribute(:status, "closed")
      |> Ash.update!(domain: Helpdesk, tenant: company.id)

      assert {:ok, []} = Sla.breached_tickets(company.id)

      other_company = create_company!()
      assert {:ok, []} = Sla.breached_tickets(other_company.id)
    end
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "SLA ticket",
      impact: "widespread",
      urgency: "critical",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "SLA Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "sla+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "SLA #{role}",
      role: role,
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "SLA Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
