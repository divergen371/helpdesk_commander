defmodule HelpdeskCommander.Helpdesk.PriorityCheck do
  @moduledoc """
  チケット本文・種別・関連タスクと現在優先度の齟齬をルールベースで判定する（HC-30）。

  - 自動で優先度を変更せず、根拠付きの提案（`needs_review?`）のみを返す
  - 人間が採用（`accept/3`）または却下（`dismiss/3`）でき、判断は `TicketEvent` に記録する
  """

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent

  require Ash.Query

  @critical_keywords [
    "全社停止",
    "サービス停止",
    "本番停止",
    "障害発生",
    "サーバーダウン",
    "サーバダウン",
    "ダウンして",
    "ダウンした",
    "接続できない",
    "ログインできない",
    "データ消失",
    "情報漏洩",
    "ランサム",
    "不正アクセス",
    "至急",
    "緊急",
    "outage",
    "production down",
    "critical"
  ]

  @significant_keywords [
    "業務に支障",
    "エラーが多発",
    "一部停止",
    "決済",
    "請求",
    "今日中",
    "本日中"
  ]

  @low_urgency_keywords [
    "急ぎません",
    "いつでも",
    "相談",
    "質問",
    "確認したい",
    "文言修正",
    "機能追加",
    "要望",
    "検討",
    "typo"
  ]

  @type evaluation :: %{
          status: :ok | :needs_review | :dismissed,
          needs_review?: boolean(),
          dismissed?: boolean(),
          risk_score: float(),
          current_priority: String.t(),
          suggested_priority: String.t(),
          reasons: [String.t()],
          fingerprint: String.t()
        }

  @doc """
  チケットと関連タスクから優先度齟齬を評価する。

  `opts`:
  - `:task_links` - 紐付いた `TicketTaskLink` 一覧（`:task` preload 済み）
  """
  @spec evaluate(Ticket.t(), keyword()) :: evaluation()
  def evaluate(%Ticket{} = ticket, opts \\ []) do
    task_links = Keyword.get(opts, :task_links, [])

    text = normalize_text("#{ticket.subject} #{ticket.description}")
    current = ticket.priority || "p3"

    {reasons, score, suggested} =
      []
      |> evaluate_high_severity_mismatch(ticket, text, current)
      |> evaluate_all_p1_mismatch(ticket, text, current)
      |> evaluate_task_mismatch(ticket, task_links, current)
      |> finalize_signals(current)

    fingerprint = build_fingerprint(current, suggested, reasons)

    dismissed? =
      reasons != [] and
        dismissed_for_fingerprint?(fetch_latest_decision_events(ticket), fingerprint)

    needs_review? = reasons != [] and score >= 0.7 and not dismissed?

    status =
      cond do
        dismissed? -> :dismissed
        needs_review? -> :needs_review
        true -> :ok
      end

    %{
      status: status,
      needs_review?: needs_review?,
      dismissed?: dismissed?,
      risk_score: Float.round(score, 2),
      current_priority: current,
      suggested_priority: suggested,
      reasons: reasons,
      fingerprint: fingerprint
    }
  end

  @doc """
  齟齬提案を採用し、チケット優先度を `suggested_priority`（`priority_source: "manual"`）へ更新して
  `TicketEvent`（`priority_check_accepted`）を記録する。
  """
  @spec accept(Ticket.t(), User.t(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def accept(%Ticket{} = ticket, %User{} = user, opts \\ []) do
    if Authorization.privileged_for_company?(user, ticket.company_id) do
      eval = evaluate(ticket, opts)

      with {:ok, updated_ticket} <- maybe_update_priority(ticket, user, eval),
           :ok <-
             record_event(ticket, user, "priority_check_accepted", %{
               from: ticket.priority,
               to: eval.suggested_priority,
               risk_score: eval.risk_score,
               reasons: eval.reasons,
               fingerprint: eval.fingerprint
             }) do
        {:ok, updated_ticket}
      end
    else
      {:error, :forbidden}
    end
  end

  @doc """
  齟齬提案を誤検知として却下し、`TicketEvent`（`priority_check_dismissed`）を記録する。
  """
  @spec dismiss(Ticket.t(), User.t(), keyword()) :: {:ok, TicketEvent.t()} | {:error, term()}
  def dismiss(%Ticket{} = ticket, %User{} = user, opts \\ []) do
    if Authorization.same_company?(user, ticket.company_id) and Authorization.internal?(user) do
      eval = evaluate(ticket, opts)

      data = %{
        priority: ticket.priority,
        suggested_priority: eval.suggested_priority,
        risk_score: eval.risk_score,
        reasons: eval.reasons,
        fingerprint: eval.fingerprint
      }

      TicketEvent
      |> Ash.Changeset.for_create(:create, %{
        event_type: "priority_check_dismissed",
        data: data,
        ticket_id: ticket.id,
        actor_id: user.id,
        company_id: ticket.company_id
      })
      |> Ash.create(domain: Helpdesk, actor: user, tenant: ticket.company_id)
    else
      {:error, :forbidden}
    end
  end

  defp evaluate_high_severity_mismatch(signals, ticket, text, current) when current in ["p3", "p4"] do
    critical_hits = matched_keywords(text, @critical_keywords)
    significant_hits = matched_keywords(text, @significant_keywords)

    signals
    |> maybe_add_critical_signal(critical_hits, current)
    |> maybe_add_significant_signal(critical_hits, significant_hits, current)
    |> maybe_add_incident_signal(ticket.type, critical_hits, significant_hits, current)
  end

  defp evaluate_high_severity_mismatch(signals, _ticket, _text, _current), do: signals

  defp maybe_add_critical_signal(signals, [], _current), do: signals

  defp maybe_add_critical_signal(signals, critical_hits, current) do
    reason =
      "本文に緊急・停止を示す語（#{Enum.join(Enum.take(critical_hits, 3), " / ")}）が含まれていますが、優先度が #{current} です"

    [{reason, 0.85, "p1"} | signals]
  end

  defp maybe_add_significant_signal(signals, [], significant_hits, current)
       when significant_hits != [] do
    reason =
      "本文に業務影響を示す語（#{Enum.join(Enum.take(significant_hits, 3), " / ")}）が含まれていますが、優先度が #{current} です"

    [{reason, 0.72, "p2"} | signals]
  end

  defp maybe_add_significant_signal(signals, _critical_hits, _significant_hits, _current),
    do: signals

  defp maybe_add_incident_signal(signals, "incident", [], [], current) do
    reason = "種別が incident（障害）ですが、優先度が #{current} のままです"
    [{reason, 0.75, "p2"} | signals]
  end

  defp maybe_add_incident_signal(signals, _type, _critical_hits, _significant_hits, _current),
    do: signals

  defp evaluate_all_p1_mismatch(signals, ticket, text, "p1") do
    critical_hits = matched_keywords(text, @critical_keywords)
    low_hits = matched_keywords(text, @low_urgency_keywords)

    if ticket.type != "incident" and critical_hits == [] and low_hits != [] do
      reason =
        "優先度が p1 ですが、障害種別ではなく低緊急度を示す語（#{Enum.join(Enum.take(low_hits, 3), " / ")}）が含まれています"

      [{reason, 0.78, "p3"} | signals]
    else
      signals
    end
  end

  defp evaluate_all_p1_mismatch(signals, _ticket, _text, _current), do: signals

  defp evaluate_task_mismatch(signals, _ticket, task_links, current) when current in ["p1", "p2"] do
    tasks =
      task_links
      |> Enum.map(&Map.get(&1, :task))
      |> Enum.reject(&(is_nil(&1) or &1.status in ["done", "cancelled"]))

    if tasks != [] and Enum.all?(tasks, &(&1.priority == "low" and is_nil(&1.due_date))) do
      reason = "優先度が #{current} ですが、未完了の関連タスクがすべて低優先度かつ期限未設定です"
      [{reason, 0.74, current} | signals]
    else
      signals
    end
  end

  defp evaluate_task_mismatch(signals, _ticket, _task_links, _current), do: signals

  defp finalize_signals([], current), do: {[], 0.0, current}

  defp finalize_signals(signals, current) do
    ordered = Enum.reverse(signals)
    reasons = Enum.map(ordered, &elem(&1, 0))
    max_score = ordered |> Enum.map(&elem(&1, 1)) |> Enum.max()

    suggested =
      ordered
      |> Enum.max_by(&elem(&1, 1))
      |> elem(2)
      |> Kernel.||(current)

    {reasons, max_score, suggested}
  end

  defp maybe_update_priority(%Ticket{priority: p} = ticket, _user, %{suggested_priority: p}) do
    {:ok, ticket}
  end

  defp maybe_update_priority(%Ticket{} = ticket, %User{} = user, %{suggested_priority: suggested}) do
    ticket
    |> Ash.Changeset.for_update(:update, %{
      priority: suggested,
      priority_source: "manual",
      actor_id: user.id
    })
    |> Ash.update(domain: Helpdesk, actor: user, tenant: ticket.company_id)
  end

  defp record_event(ticket, user, event_type, data) do
    case TicketEvent
         |> Ash.Changeset.for_create(:create, %{
           event_type: event_type,
           data: data,
           ticket_id: ticket.id,
           actor_id: user.id,
           company_id: ticket.company_id
         })
         |> Ash.create(domain: Helpdesk, actor: user, tenant: ticket.company_id) do
      {:ok, _event} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_latest_decision_events(%Ticket{id: ticket_id, company_id: company_id}) do
    TicketEvent
    |> Ash.Query.filter(
      ticket_id == ^ticket_id and
        event_type in ["priority_check_dismissed", "priority_check_accepted"]
    )
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!(domain: Helpdesk, tenant: company_id, authorize?: false)
  end

  defp dismissed_for_fingerprint?(events, fingerprint) do
    latest_decision =
      events
      |> Enum.filter(&(&1.event_type in ["priority_check_dismissed", "priority_check_accepted"]))
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> List.first()

    case latest_decision do
      %TicketEvent{event_type: "priority_check_dismissed", data: data} when is_map(data) ->
        (Map.get(data, "fingerprint") || Map.get(data, :fingerprint)) == fingerprint

      _other ->
        false
    end
  end

  defp build_fingerprint(current, suggested, reasons) do
    payload = :erlang.term_to_binary({current, suggested, Enum.sort(reasons)})
    :sha256 |> :crypto.hash(payload) |> Base.encode16(case: :lower)
  end

  defp matched_keywords(text, keywords) do
    Enum.filter(keywords, fn kw ->
      downcased = String.downcase(kw)

      if Regex.match?(~r/^[a-z0-9\s]+$/, downcased) do
        Regex.match?(~r/\b#{Regex.escape(downcased)}\b/, text)
      else
        String.contains?(text, downcased)
      end
    end)
  end

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.trim()
  end
end
