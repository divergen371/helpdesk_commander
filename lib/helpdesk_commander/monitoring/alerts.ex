defmodule HelpdeskCommander.Monitoring.Alerts do
  @moduledoc """
  監視サービスからのアラートを受け取り、チケットへ変換する。

  汎用 JSON と Alertmanager / Grafana 形式の `alerts` 配列を受け付ける。
  `source` と `fingerprint` で同一アラートを識別し、チケットが閉じられるまでは
  同じ fingerprint の firing を重複起票しない。
  """

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.MonitoringAlert
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Support.CompanyCode
  alias HelpdeskCommander.Support.PiiHash

  @priority_by_severity %{
    "critical" => "p1",
    "error" => "p2",
    "warning" => "p2",
    "info" => "p3"
  }

  @open_statuses ~w(new triage in_progress waiting resolved verified)

  @spec enabled?() :: boolean()
  def enabled?, do: is_binary(config(:token)) and config(:token) != ""

  @spec token_valid?(String.t() | nil) :: boolean()
  def token_valid?(token) when is_binary(token) do
    case config(:token) do
      expected when is_binary(expected) and expected != "" ->
        byte_size(expected) == byte_size(token) and Plug.Crypto.secure_compare(expected, token)

      _other ->
        false
    end
  end

  def token_valid?(_token), do: false

  @spec ingest(map()) :: {:ok, [map()]} | {:error, term()}
  def ingest(payload) when is_map(payload) do
    with {:ok, company} <- configured_company(),
         {:ok, product} <- configured_product(company),
         {:ok, system_user} <- system_user(company.id),
         {:ok, alerts} <- normalize(payload) do
      ingest_all(alerts, company, product, system_user)
    end
  end

  def ingest(_payload), do: {:error, :invalid_payload}

  @doc "Webhook のペイロードを正規化する。"
  @spec normalize(map()) :: {:ok, [map()]} | {:error, term()}
  def normalize(payload) when is_map(payload) do
    source = string_value(payload["source"]) || "monitoring"

    raw_alerts =
      case payload["alerts"] do
        alerts when is_list(alerts) and alerts != [] -> alerts
        _other -> [payload]
      end

    alerts = raw_alerts |> Enum.map(&normalize_alert(&1, payload, source)) |> Enum.reject(&is_nil/1)

    if alerts == [] do
      {:error, :invalid_payload}
    else
      {:ok, alerts}
    end
  end

  def normalize(_payload), do: {:error, :invalid_payload}

  defp normalize_alert(raw, envelope, source) when is_map(raw) do
    labels = merge_maps(envelope["commonLabels"], raw["labels"])
    annotations = merge_maps(envelope["commonAnnotations"], raw["annotations"])

    title =
      first_present([
        raw["title"],
        labels["alertname"],
        annotations["summary"],
        envelope["title"]
      ])

    if is_binary(title) and String.trim(title) != "" do
      description =
        first_present([
          raw["description"],
          annotations["description"],
          annotations["summary"],
          envelope["description"]
        ])

      severity =
        normalize_severity(first_present([raw["severity"], labels["severity"], envelope["severity"]]))

      status = normalize_status(first_present([raw["status"], envelope["status"], "firing"]))

      fingerprint =
        first_present([raw["fingerprint"], envelope["fingerprint"]]) ||
          build_fingerprint(source, title, labels)

      %{
        source: truncate(source, 100),
        fingerprint: truncate(to_string(fingerprint), 128),
        status: status,
        severity: severity,
        title: truncate(String.trim(title), 200),
        description: description,
        payload: raw
      }
    end
  end

  defp normalize_alert(_raw, _envelope, _source), do: nil

  defp ingest_all(alerts, company, product, system_user) do
    result =
      Enum.reduce_while(alerts, {:ok, []}, fn alert, {:ok, results} ->
        case ingest_alert(alert, company, product, system_user) do
          {:ok, result} -> {:cont, {:ok, [result | results]}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  defp ingest_alert(%{status: "resolved"} = alert, company, _product, system_user) do
    case find_alert(company.id, alert) do
      {:ok, nil} ->
        {:ok, %{alert: nil, ticket: nil, duplicate?: false, ignored?: true}}

      {:ok, %MonitoringAlert{} = existing} ->
        {:ok, resolved_alert(existing, alert, company, system_user)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ingest_alert(alert, company, product, system_user) do
    case find_alert(company.id, alert) do
      {:ok, nil} ->
        create_alert_and_ticket(alert, company, product, system_user)

      {:ok, %MonitoringAlert{} = existing} ->
        duplicate_or_recreate(existing, alert, company, product, system_user)

      {:error, error} ->
        {:error, error}
    end
  end

  defp duplicate_or_recreate(existing, alert, company, product, system_user) do
    with {:ok, ticket} <- load_alert_ticket(existing, company.id) do
      if ticket && ticket.status in @open_statuses do
        {:ok, duplicate_alert(existing, alert, company, ticket)}
      else
        create_replacement_ticket(existing, alert, company, product, system_user)
      end
    end
  end

  defp duplicate_alert(existing, alert, company, ticket) do
    now = DateTime.utc_now()

    {:ok, updated} =
      existing
      |> Ash.Changeset.for_update(:update, %{
        status: "firing",
        severity: alert.severity,
        title: alert.title,
        description: alert.description,
        payload: alert.payload,
        last_seen_at: now,
        resolved_at: nil
      })
      |> Ash.update(domain: Helpdesk, tenant: company.id)

    %{alert: updated, ticket: ticket, duplicate?: true, ignored?: false}
  end

  defp resolved_alert(existing, alert, company, system_user) do
    now = DateTime.utc_now()

    {:ok, updated} =
      existing
      |> Ash.Changeset.for_update(:update, %{
        status: "resolved",
        severity: alert.severity,
        title: alert.title,
        description: alert.description,
        payload: alert.payload,
        last_seen_at: now,
        resolved_at: now
      })
      |> Ash.update(domain: Helpdesk, tenant: company.id)

    ticket =
      case load_alert_ticket(updated, company.id) do
        {:ok, value} -> value
        _error -> nil
      end

    _message = notify_recovery(ticket, updated, system_user, company.id)

    %{alert: updated, ticket: ticket, duplicate?: false, ignored?: false}
  end

  defp create_alert_and_ticket(alert, company, product, system_user) do
    with {:ok, ticket} <- create_ticket(alert, product, system_user),
         {:ok, monitoring_alert} <- create_alert(alert, company, ticket) do
      {:ok, %{alert: monitoring_alert, ticket: ticket, duplicate?: false, ignored?: false}}
    end
  end

  defp create_replacement_ticket(existing, alert, company, product, system_user) do
    with {:ok, ticket} <- create_ticket(alert, product, system_user),
         {:ok, updated} <-
           existing
           |> Ash.Changeset.for_update(:update, %{
             ticket_id: ticket.id,
             status: "firing",
             severity: alert.severity,
             title: alert.title,
             description: alert.description,
             payload: alert.payload,
             last_seen_at: DateTime.utc_now(),
             resolved_at: nil
           })
           |> Ash.update(domain: Helpdesk, tenant: company.id) do
      {:ok, %{alert: updated, ticket: ticket, duplicate?: false, ignored?: false}}
    end
  end

  defp create_ticket(alert, product, system_user) do
    result =
      Helpdesk.create_ticket(%{
        subject: truncate("[Alert] #{alert.title}", 200),
        description: alert_description(alert),
        type: "incident",
        priority: Map.get(@priority_by_severity, alert.severity, "p3"),
        product_id: product.id,
        requester_id: system_user.id
      })

    case result do
      {:ok, ticket} ->
        _event =
          TicketEvent
          |> Ash.Changeset.for_create(:create, %{
            event_type: "monitoring_alert_received",
            data: %{
              source: alert.source,
              fingerprint: alert.fingerprint,
              severity: alert.severity
            },
            ticket_id: ticket.id,
            actor_id: system_user.id,
            company_id: ticket.company_id
          })
          |> Ash.create!(domain: Helpdesk)

        {:ok, ticket}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_alert(alert, company, ticket) do
    now = DateTime.utc_now()

    MonitoringAlert
    |> Ash.Changeset.for_create(:create, %{
      company_id: company.id,
      ticket_id: ticket.id,
      source: alert.source,
      fingerprint: alert.fingerprint,
      status: "firing",
      severity: alert.severity,
      title: alert.title,
      description: alert.description,
      payload: alert.payload,
      first_seen_at: now,
      last_seen_at: now
    })
    |> Ash.create(domain: Helpdesk, tenant: company.id)
  end

  defp notify_recovery(nil, _alert, _system_user, _company_id), do: :ok

  defp notify_recovery(%Ticket{} = ticket, alert, system_user, company_id) do
    with {:ok, conversation} <- Helpdesk.ensure_conversation(ticket, "internal_public") do
      ConversationMessage
      |> Ash.Changeset.for_create(:create, %{
        company_id: company_id,
        conversation_id: conversation.id,
        sender_id: system_user.id,
        body: "監視アラートが復旧しました: #{alert.title}",
        message_type: "message",
        body_format: "plain",
        meta: %{"source" => "monitoring", "fingerprint" => alert.fingerprint}
      })
      |> Ash.create(domain: Helpdesk, tenant: company_id)
    end
  end

  defp find_alert(company_id, alert) do
    MonitoringAlert
    |> filter(source == ^alert.source and fingerprint == ^alert.fingerprint)
    |> Ash.read_one(domain: Helpdesk, tenant: company_id)
  end

  defp load_alert_ticket(%MonitoringAlert{ticket_id: nil}, _company_id), do: {:ok, nil}

  defp load_alert_ticket(%MonitoringAlert{ticket_id: ticket_id}, company_id) do
    Ticket
    |> filter(id == ^ticket_id)
    |> Ash.read_one(domain: Helpdesk, tenant: company_id)
  end

  defp configured_company do
    code = config(:company_code) || "A-000001"

    with {:ok, hash} <- CompanyCode.hash(code),
         {:ok, %Company{} = company} <-
           Company
           |> filter(company_code_hash == ^hash)
           |> Ash.read_one(domain: Accounts) do
      {:ok, company}
    else
      {:ok, nil} -> {:error, :company_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp configured_product(company) do
    case config(:product_id) do
      nil ->
        first_product(company.id)

      value ->
        value_string = to_string(value)

        case Integer.parse(value_string) do
          {product_id, ""} ->
            product_result =
              Ash.get(HelpdeskCommander.Helpdesk.Product, product_id,
                domain: Helpdesk,
                tenant: company.id
              )

            case product_result do
              {:ok, %HelpdeskCommander.Helpdesk.Product{} = product} -> {:ok, product}
              _error -> first_product(company.id)
            end

          _error ->
            first_product(company.id)
        end
    end
  end

  defp first_product(company_id) do
    case Helpdesk.list_products(company_id, active_only: true) do
      {:ok, [product | _rest]} -> {:ok, product}
      {:ok, []} -> {:error, :product_not_configured}
      {:error, error} -> {:error, error}
    end
  end

  defp system_user(company_id) do
    email = "monitoring+#{company_id}@helpdesk.local"
    email_hash = PiiHash.email(email)

    case read_system_user(company_id, email_hash) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:ok, nil} ->
        create_system_user(company_id, email)

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_system_user(company_id, email_hash) do
    User
    |> filter(company_id == ^company_id and email_hash == ^email_hash)
    |> Ash.read_one(domain: Accounts, tenant: company_id)
  end

  defp create_system_user(company_id, email) do
    result =
      User
      |> Ash.Changeset.for_create(:create, %{
        company_id: company_id,
        email: email,
        display_name: "Monitoring",
        role: "system",
        status: "active"
      })
      |> Ash.create(domain: Accounts, tenant: company_id)

    case result do
      {:ok, user} -> {:ok, user}
      {:error, error} -> retry_system_user(company_id, email, error)
    end
  end

  defp retry_system_user(company_id, email, original_error) do
    case read_system_user(company_id, PiiHash.email(email)) do
      {:ok, %User{} = user} -> {:ok, user}
      _result -> {:error, original_error}
    end
  end

  defp alert_description(alert) do
    details =
      alert.payload
      |> Map.take(["labels", "annotations", "service", "source", "fingerprint"])
      |> inspect(pretty: true)

    description = """
    監視サービスから受信したアラートです。

    重要度: #{alert.severity}
    状態: #{alert.status}
    ソース: #{alert.source}
    fingerprint: #{alert.fingerprint}

    #{alert.description || ""}

    詳細:
    #{details}
    """

    String.trim(description)
  end

  defp build_fingerprint(source, title, labels) do
    material =
      Enum.join(
        [source, title | Enum.map(Enum.sort(labels), fn {key, value} -> "#{key}=#{value}" end)],
        "|"
      )

    hash = :crypto.hash(:sha256, material)
    encoded = Base.encode16(hash, case: :lower)
    String.slice(encoded, 0, 32)
  end

  defp normalize_severity(value) do
    case value |> to_string() |> String.downcase() do
      "critical" -> "critical"
      "page" -> "critical"
      "error" -> "error"
      "high" -> "error"
      "warning" -> "warning"
      "warn" -> "warning"
      "info" -> "info"
      "low" -> "info"
      _other -> "warning"
    end
  end

  defp normalize_status("resolved"), do: "resolved"
  defp normalize_status(_status), do: "firing"

  defp first_present(values), do: Enum.find(values, &present?/1)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp string_value(value) when is_binary(value) and value != "", do: value
  defp string_value(_value), do: nil

  defp merge_maps(left, right) when is_map(left) and is_map(right), do: Map.merge(left, right)
  defp merge_maps(left, _right) when is_map(left), do: left
  defp merge_maps(_left, right) when is_map(right), do: right
  defp merge_maps(_left, _right), do: %{}

  defp truncate(value, max) when byte_size(value) <= max, do: value
  defp truncate(value, max), do: String.slice(value, 0, max)

  defp config(key), do: Application.get_env(:helpdesk_commander, __MODULE__, [])[key]
end
