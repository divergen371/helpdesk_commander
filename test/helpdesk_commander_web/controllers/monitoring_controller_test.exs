defmodule HelpdeskCommanderWeb.MonitoringControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
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

    %{company: company}
  end

  test "accepts a signed alert and creates a ticket", %{conn: conn} do
    payload = %{
      "source" => "prometheus",
      "fingerprint" => "http-fp",
      "status" => "firing",
      "severity" => "critical",
      "title" => "HTTP alert"
    }

    conn =
      conn
      |> json_conn()
      |> put_req_header("x-monitoring-token", "monitor-secret")
      |> post("/integrations/monitoring/alerts", Jason.encode!(payload))

    body = json_response(conn, 202)
    [result] = body["results"]
    assert result["duplicate"] == false
    assert result["fingerprint"] == "http-fp"
    assert is_binary(result["ticket_public_id"])
  end

  test "rejects a request with the wrong token", %{conn: conn} do
    conn =
      conn
      |> json_conn()
      |> put_req_header("x-monitoring-token", "wrong")
      |> post("/integrations/monitoring/alerts", Jason.encode!(%{"title" => "x"}))

    assert response(conn, 401) == "invalid token"
  end

  test "returns 503 when the integration is disabled", %{conn: conn} do
    Application.delete_env(:helpdesk_commander, Alerts)

    conn =
      conn
      |> json_conn()
      |> post("/integrations/monitoring/alerts", Jason.encode!(%{"title" => "x"}))

    assert response(conn, 503) == "monitoring integration is disabled"
  end

  test "returns duplicate=true for a repeated alert", %{conn: conn} do
    payload = %{
      "source" => "grafana",
      "fingerprint" => "repeat-http",
      "status" => "firing",
      "severity" => "warning",
      "title" => "Repeated alert"
    }

    first = send_alert(conn, payload)
    assert [%{"duplicate" => false}] = json_response(first, 202)["results"]

    second = send_alert(recycle(conn), payload)
    assert [%{"duplicate" => true}] = json_response(second, 202)["results"]
  end

  test "accepts an Alertmanager payload", %{conn: conn} do
    payload = %{
      "status" => "firing",
      "alerts" => [
        %{
          "status" => "firing",
          "fingerprint" => "am-http",
          "labels" => %{"alertname" => "DiskFull", "severity" => "warning"},
          "annotations" => %{"summary" => "disk full"}
        }
      ]
    }

    conn = send_alert(conn, payload)

    assert [%{"ticket_public_id" => public_id}] = json_response(conn, 202)["results"]
    assert is_binary(public_id)
  end

  defp send_alert(conn, payload) do
    conn
    |> json_conn()
    |> put_req_header("x-monitoring-token", "monitor-secret")
    |> post("/integrations/monitoring/alerts", Jason.encode!(payload))
  end

  defp json_conn(conn), do: put_req_header(conn, "content-type", "application/json")

  defp create_company!(code) do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Monitoring HTTP Company #{System.unique_integer([:positive])}",
      company_code: code
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Monitoring HTTP Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
