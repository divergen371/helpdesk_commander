defmodule HelpdeskCommander.Helpdesk.Sla do
  @moduledoc """
  優先度ごとの SLA 目標と、チケットの達成/逸脱判定を扱う。

  目標時間の単位は分。会社ごとの `SlaPolicy` が未設定の優先度は既定値を使う。
  一次応答は `first_response_at`、解決は `resolved_at` で判定する。暫定対応と復旧は
  Incident のタイムライン（mitigation / recovery）の最早記録で判定する。Incident が
  ないチケットでは暫定対応・復旧を対象外とする。
  """

  import Ash.Query

  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Incident
  alias HelpdeskCommander.Helpdesk.IncidentEvent
  alias HelpdeskCommander.Helpdesk.SlaPolicy
  alias HelpdeskCommander.Helpdesk.Ticket

  @priorities ~w(p1 p2 p3 p4)

  @defaults %{
    "p1" => %{first_response: 15, mitigation: 60, resolution: 240, restoration: 480},
    "p2" => %{first_response: 60, mitigation: 240, resolution: 1_440, restoration: 2_880},
    "p3" => %{first_response: 240, mitigation: 1_440, resolution: 4_320, restoration: 7_200},
    "p4" => %{first_response: 480, mitigation: 2_880, resolution: 8_640, restoration: 14_400}
  }

  @metric_labels %{
    first_response: "一次応答",
    mitigation: "暫定対応",
    resolution: "解決",
    restoration: "復旧"
  }

  @spec priorities() :: [String.t()]
  def priorities, do: @priorities

  @spec metric_label(atom()) :: String.t()
  def metric_label(metric), do: Map.get(@metric_labels, metric, to_string(metric))

  @doc "優先度の既定目標（分）。未知の優先度は nil。"
  @spec default_targets(String.t()) :: map() | nil
  def default_targets(priority), do: Map.get(@defaults, priority)

  @doc """
  会社の全優先度の目標を返す。

  各要素は `%{priority: "p1", targets: %{...}, source: :configured | :default}`。
  """
  @spec list_targets(integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_targets(company_id, opts \\ []) do
    with {:ok, policies} <- read_policies(company_id, opts) do
      {:ok,
       Enum.map(@priorities, fn priority ->
         targets = targets_for(priority, policies)
         %{priority: priority, targets: targets, source: source_for(priority, policies)}
       end)}
    end
  end

  @doc "指定優先度の目標（分）。"
  @spec get_targets(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_targets(company_id, priority, opts \\ []) do
    if priority in @priorities do
      with {:ok, policies} <- read_policies(company_id, opts) do
        {:ok, targets_for(priority, policies)}
      end
    else
      {:error, :unknown_priority}
    end
  end

  @doc "優先度の目標を保存する（未作成なら作成）。"
  @spec save_policy(integer(), String.t(), map(), map(), keyword()) ::
          {:ok, SlaPolicy.t()} | {:error, term()}
  def save_policy(company_id, priority, attrs, actor, opts \\ []) do
    attrs = Map.drop(attrs, ["priority", :priority, "company_id", :company_id])

    with :ok <- ensure_privileged(actor, company_id) do
      if priority in @priorities do
        case find_policy(company_id, priority, opts) do
          {:ok, nil} ->
            SlaPolicy
            |> Ash.Changeset.for_create(
              :create,
              Map.merge(attrs, %{company_id: company_id, priority: priority})
            )
            |> Ash.create(domain: Helpdesk, actor: actor, tenant: company_id)

          {:ok, %SlaPolicy{} = policy} ->
            policy
            |> Ash.Changeset.for_update(:update, attrs)
            |> Ash.update(domain: Helpdesk, actor: actor, tenant: company_id)

          {:error, error} ->
            {:error, error}
        end
      else
        {:error, :unknown_priority}
      end
    end
  end

  @doc """
  チケット 1 件の SLA 判定を返す。

  `context` に `%{incident: incident | nil, events: [IncidentEvent.t()]}` を渡すと
  再取得を省ける。省略時はこの関数内で読み込む。
  """
  @spec evaluate(Ticket.t(), map(), map(), DateTime.t()) :: map()
  def evaluate(ticket, targets, context \\ %{}, now \\ DateTime.utc_now()) do
    context = if map_size(context) == 0, do: load_context(ticket), else: context
    incident = Map.get(context, :incident)
    events = Map.get(context, :events, [])
    incident? = not is_nil(incident)

    metrics = [
      build_metric(
        :first_response,
        targets.first_response,
        ticket.inserted_at,
        ticket.first_response_at,
        now,
        true
      ),
      build_metric(
        :mitigation,
        targets.mitigation,
        ticket.inserted_at,
        phase_finished_at(events, "mitigation"),
        now,
        incident?
      ),
      build_metric(
        :resolution,
        targets.resolution,
        ticket.inserted_at,
        ticket.resolved_at,
        now,
        true
      ),
      build_metric(
        :restoration,
        targets.restoration,
        ticket.inserted_at,
        phase_finished_at(events, "recovery"),
        now,
        incident?
      )
    ]

    %{ticket: ticket, metrics: metrics, breached?: Enum.any?(metrics, &(&1.status == :breached))}
  end

  @doc "未クローズのチケットで、いずれかの SLA を逸脱している件数を返す。"
  @spec breach_count(integer(), keyword()) :: {:ok, non_neg_integer()} | {:error, Exception.t()}
  def breach_count(company_id, opts \\ []) do
    with {:ok, evaluated} <- breached_tickets(company_id, :all, opts) do
      {:ok, length(evaluated)}
    end
  end

  @doc "未クローズのチケットのうち、SLA 逸脱のあるものを返す。"
  @spec breached_tickets(integer(), non_neg_integer() | :all, keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def breached_tickets(company_id, limit \\ 5, opts \\ []) do
    with {:ok, tickets} <- read_open_tickets(company_id, opts),
         {:ok, targets_by_priority} <- targets_by_priority(company_id, opts),
         {:ok, incidents} <- read_incidents(company_id, opts),
         {:ok, events} <- read_events(company_id, opts) do
      incident_by_ticket = Map.new(incidents, &{&1.ticket_id, &1})
      events_by_incident = Enum.group_by(events, & &1.incident_id)
      now = Keyword.get(opts, :now, DateTime.utc_now())

      evaluated =
        tickets
        |> Enum.map(fn ticket ->
          incident = Map.get(incident_by_ticket, ticket.id)

          context = %{
            incident: incident,
            events: if(incident, do: Map.get(events_by_incident, incident.id, []), else: [])
          }

          targets = Map.fetch!(targets_by_priority, ticket.priority)
          evaluate(ticket, targets, context, now)
        end)
        |> Enum.filter(& &1.breached?)

      {:ok, apply_limit(evaluated, limit)}
    end
  end

  defp read_policies(company_id, opts) do
    SlaPolicy
    |> filter(company_id == ^company_id)
    |> Ash.read(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  defp find_policy(company_id, priority, opts) do
    SlaPolicy
    |> filter(company_id == ^company_id and priority == ^priority)
    |> Ash.read_one(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  defp read_open_tickets(company_id, opts) do
    Ticket
    |> filter(company_id == ^company_id and status != "closed")
    |> sort(inserted_at: :asc)
    |> Ash.read(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  defp read_incidents(company_id, opts) do
    Incident
    |> filter(company_id == ^company_id)
    |> Ash.read(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  defp read_events(company_id, opts) do
    IncidentEvent
    |> filter(company_id == ^company_id)
    |> Ash.read(domain: Helpdesk, tenant: company_id, authorize?: Keyword.get(opts, :authorize?, true))
  end

  defp targets_by_priority(company_id, opts) do
    with {:ok, policies} <- read_policies(company_id, opts) do
      {:ok, Map.new(@priorities, &{&1, targets_for(&1, policies)})}
    end
  end

  defp targets_for(priority, policies) do
    defaults = Map.fetch!(@defaults, priority)

    case Enum.find(policies, &(&1.priority == priority)) do
      nil ->
        defaults

      policy ->
        %{
          first_response: policy.first_response_minutes,
          mitigation: policy.mitigation_minutes,
          resolution: policy.resolution_minutes,
          restoration: policy.restoration_minutes
        }
    end
  end

  defp source_for(priority, policies) do
    if Enum.any?(policies, &(&1.priority == priority)), do: :configured, else: :default
  end

  defp build_metric(key, _target, _start, _finished, _now, false) do
    %{
      key: key,
      label: metric_label(key),
      target_minutes: nil,
      status: :not_applicable,
      due_at: nil,
      finished_at: nil,
      elapsed_minutes: nil,
      remaining_minutes: nil
    }
  end

  defp build_metric(key, target, start, finished, now, true) do
    due_at = add_minutes(start, target)
    elapsed_at = finished || now
    elapsed_minutes = DateTime.diff(elapsed_at, start, :minute)
    remaining_minutes = DateTime.diff(due_at, now, :minute)

    status =
      cond do
        finished && DateTime.compare(finished, due_at) != :gt -> :met
        finished -> :breached
        DateTime.compare(now, due_at) == :gt -> :breached
        true -> :pending
      end

    %{
      key: key,
      label: metric_label(key),
      target_minutes: target,
      status: status,
      due_at: due_at,
      finished_at: finished,
      elapsed_minutes: max(elapsed_minutes, 0),
      remaining_minutes: remaining_minutes
    }
  end

  defp add_minutes(%DateTime{} = start, minutes), do: DateTime.add(start, minutes * 60, :second)

  defp phase_finished_at(events, phase) do
    events
    |> Enum.filter(&(&1.phase == phase))
    |> Enum.map(& &1.inserted_at)
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp apply_limit(items, :all), do: items
  defp apply_limit(items, limit) when is_integer(limit), do: Enum.take(items, limit)

  defp load_context(ticket) do
    with {:ok, incident} <- Helpdesk.get_incident(ticket.id, tenant: ticket.company_id),
         {:ok, events} <-
           if(incident,
             do: Helpdesk.list_incident_events(incident.id, tenant: ticket.company_id),
             else: {:ok, []}
           ) do
      %{incident: incident, events: events}
    else
      _error -> %{incident: nil, events: []}
    end
  end

  defp ensure_privileged(%{role: role, company_id: company_id}, company_id) do
    if Authorization.privileged_role?(role), do: :ok, else: {:error, :forbidden}
  end

  defp ensure_privileged(_actor, _company_id), do: {:error, :forbidden}
end
