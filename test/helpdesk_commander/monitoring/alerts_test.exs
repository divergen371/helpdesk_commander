defmodule HelpdeskCommander.Monitoring.AlertsTest do
  use HelpdeskCommander.DataCase, async: false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.MonitoringAlert
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Monitoring.Alerts

  setup do
    company_code = unique_company_code()
    company = create_company!(company_code)
    product = create_product!(company)

    Application.put_env(:helpdesk_commander, Alerts,
      token: "monitor-secret",
      company_code: company_code,
      product_id: to_string(product.id)
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, Alerts) end)

    %{company: company, product: product}
  end

  test "creates an incident ticket from a critical alert", %{company: company} do
    payload = %{
      "source" => "prometheus",
      "fingerprint" => "fp-critical",
      "status" => "firing",
      "severity" => "critical",
      "title" => "CPU usage high",
      "description" => "CPU is above 95%"
    }

    assert {:ok, [result]} = Alerts.ingest(payload)
    assert result.duplicate? == false

    ticket = result.ticket
    assert ticket.type == "incident"
    assert ticket.priority == "p1"
    assert ticket.status == "new"
    assert ticket.subject == "[Alert] CPU usage high"

    requester = Ash.get!(HelpdeskCommander.Accounts.User, ticket.requester_id, domain: Accounts)
    assert requester.role == "system"

    assert result.alert.status == "firing"
    assert result.alert.severity == "critical"
    assert event_count(ticket.id, "monitoring_alert_received") == 1
    assert alert_count(company.id) == 1
  end

  test "suppresses a repeated firing alert for the same open ticket", %{company: company} do
    payload = %{
      "source" => "prometheus",
      "fingerprint" => "fp-duplicate",
      "status" => "firing",
      "severity" => "warning",
      "title" => "Disk usage high"
    }

    assert {:ok, [first]} = Alerts.ingest(payload)
    assert {:ok, [second]} = Alerts.ingest(payload)

    assert second.duplicate? == true
    assert second.ticket.id == first.ticket.id
    assert ticket_count(company.id) == 1
    assert alert_count(company.id) == 1
  end

  test "records recovery without closing the ticket", %{company: company} do
    payload = %{
      "source" => "prometheus",
      "fingerprint" => "fp-recovery",
      "status" => "firing",
      "severity" => "warning",
      "title" => "Queue backlog"
    }

    assert {:ok, [firing]} = Alerts.ingest(payload)
    resolved = Map.put(payload, "status", "resolved")

    assert {:ok, [result]} = Alerts.ingest(resolved)
    assert result.alert.status == "resolved"
    assert result.alert.resolved_at != nil
    assert result.ticket.status == "new"

    messages =
      ConversationMessage
      |> filter(conversation_id == ^public_conversation_id(firing.ticket))
      |> Ash.read!(domain: Helpdesk, tenant: company.id)

    assert Enum.any?(messages, &String.contains?(&1.body, "監視アラートが復旧しました"))
  end

  test "creates a new ticket when the previous ticket is closed", %{company: company} do
    payload = %{
      "source" => "prometheus",
      "fingerprint" => "fp-reopen",
      "status" => "firing",
      "severity" => "critical",
      "title" => "DB down"
    }

    assert {:ok, [first]} = Alerts.ingest(payload)
    close_ticket!(first.ticket)

    assert {:ok, [second]} = Alerts.ingest(payload)
    assert second.ticket.id != first.ticket.id
    assert second.alert.ticket_id == second.ticket.id
    assert alert_count(company.id) == 1
    assert ticket_count(company.id) == 2
  end

  test "accepts Alertmanager style payloads" do
    payload = %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "fp-alertmanager",
          "labels" => %{
            "alertname" => "DiskFull",
            "severity" => "warning",
            "instance" => "db1"
          },
          "annotations" => %{"summary" => "Disk is almost full"}
        }
      ]
    }

    assert {:ok, [result]} = Alerts.ingest(payload)
    assert result.ticket.subject == "[Alert] DiskFull"
    assert result.ticket.priority == "p2"
  end

  test "derives a stable fingerprint when none is supplied", %{company: company} do
    payload = %{
      "source" => "grafana",
      "status" => "firing",
      "severity" => "info",
      "title" => "Certificate expires soon",
      "labels" => %{"service" => "web"}
    }

    assert {:ok, [first]} = Alerts.ingest(payload)
    assert {:ok, [second]} = Alerts.ingest(payload)

    assert second.duplicate? == true
    assert second.ticket.id == first.ticket.id
    assert alert_count(company.id) == 1
  end

  test "rejects payloads without a title" do
    assert {:error, :invalid_payload} = Alerts.ingest(%{"status" => "firing"})
  end

  defp close_ticket!(ticket) do
    ticket
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:status, "closed")
    |> Ash.update!(domain: Helpdesk, tenant: ticket.company_id)
  end

  defp public_conversation_id(ticket) do
    {:ok, conversation} = Helpdesk.ensure_conversation(ticket, "internal_public")
    conversation.id
  end

  defp event_count(ticket_id, event_type) do
    TicketEvent
    |> filter(ticket_id == ^ticket_id and event_type == ^event_type)
    |> Ash.read!(domain: Helpdesk)
    |> length()
  end

  defp alert_count(company_id) do
    MonitoringAlert |> Ash.read!(domain: Helpdesk, tenant: company_id) |> length()
  end

  defp ticket_count(company_id) do
    Ticket |> Ash.read!(domain: Helpdesk, tenant: company_id) |> length()
  end

  defp create_company!(code) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Monitoring Company #{System.unique_integer([:positive])}",
      company_code: code
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Monitoring Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}" |> String.slice(0, 8)
  end
end
