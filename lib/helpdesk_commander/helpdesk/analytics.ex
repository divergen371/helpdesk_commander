defmodule HelpdeskCommander.Helpdesk.Analytics do
  @moduledoc """
  チケットの運用状況を集計する。

  期間はチケットの作成日時（`inserted_at`）で絞り、UTC の日付として扱う。
  未対応は `new` / `triage` / `in_progress` / `waiting`、未着手は `new` / `triage`。
  滞留は未対応のまま既定 24 時間を超えているチケットを指す。担当者別負荷は
  期間内に作成され、まだ未対応のチケットを担当者ごとに数える。
  """

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @open_statuses ~w(new triage in_progress waiting)
  @untouched_statuses ~w(new triage)
  @default_stalled_hours 24

  @spec open_statuses() :: [String.t()]
  def open_statuses, do: @open_statuses

  @spec default_stalled_hours() :: 24
  def default_stalled_hours, do: @default_stalled_hours

  @doc "既定の集計期間（直近30日、今日を含む）。"
  @spec default_period(Date.t()) :: {Date.t(), Date.t()}
  def default_period(today \\ Date.utc_today()) do
    {Date.add(today, -29), today}
  end

  @doc """
  期間内のチケットを集計する。

  `opts`:
  - `:from` / `:to` - `Date.t()`。省略時は直近30日
  - `:now` - 滞留判定の基準時刻
  - `:stalled_hours` - 滞留とみなす時間（既定24）
  """
  @spec summarize(integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def summarize(company_id, opts \\ []) do
    {from, to} = period(opts)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    stalled_hours = Keyword.get(opts, :stalled_hours, @default_stalled_hours)
    {from_dt, to_dt} = period_bounds(from, to)

    with {:ok, tickets} <-
           Ticket
           |> filter(company_id == ^company_id and inserted_at >= ^from_dt and inserted_at < ^to_dt)
           |> Ash.read(domain: Helpdesk, tenant: company_id),
         {:ok, users} <- Accounts.list_users(company_id) do
      open_tickets = Enum.filter(tickets, &(&1.status in @open_statuses))

      {:ok,
       %{
         period: %{from: from, to: to},
         stalled_hours: stalled_hours,
         total_count: length(tickets),
         open_count: length(open_tickets),
         untouched_count: Enum.count(tickets, &(&1.status in @untouched_statuses)),
         stalled_count: Enum.count(open_tickets, &(age_hours(now, &1.inserted_at) >= stalled_hours)),
         average_open_age_hours: average_age_hours(now, open_tickets),
         by_status: count_by(tickets, :status),
         by_priority: count_by(open_tickets, :priority),
         by_assignee: by_assignee(open_tickets, users, now)
       }}
    end
  end

  @doc "集計結果を CSV 文字列にする。"
  @spec to_csv(map()) :: String.t()
  def to_csv(summary) do
    header = ["section", "key", "count", "average_age_hours"]

    rows =
      [
        ["period", "from", summary.period.from, ""],
        ["period", "to", summary.period.to, ""],
        ["summary", "total_count", summary.total_count, ""],
        ["summary", "open_count", summary.open_count, ""],
        ["summary", "untouched_count", summary.untouched_count, ""],
        ["summary", "stalled_count", summary.stalled_count, ""],
        ["summary", "average_open_age_hours", "", summary.average_open_age_hours]
      ] ++
        Enum.map(summary.by_status, &["status", &1.key, &1.count, ""]) ++
        Enum.map(summary.by_priority, &["priority", &1.key, &1.count, ""]) ++
        Enum.map(summary.by_assignee, &["assignee", &1.key, &1.count, &1.average_age_hours])

    ([header] ++ rows)
    |> Enum.map_join("\n", fn row -> Enum.map_join(row, ",", &escape/1) end)
    |> Kernel.<>("\n")
  end

  defp by_assignee(open_tickets, users, now) do
    users_by_id = Map.new(users, &{&1.id, &1})
    grouped = Enum.group_by(open_tickets, & &1.assignee_id)

    grouped
    |> Enum.map(fn {assignee_id, tickets} ->
      %{
        key: assignee_label(assignee_id, users_by_id),
        assignee_id: assignee_id,
        count: length(tickets),
        average_age_hours: average_age_hours(now, tickets)
      }
    end)
    |> Enum.sort_by(fn row -> {-row.count, row.key} end)
  end

  defp assignee_label(nil, _users_by_id), do: "未割り当て"

  defp assignee_label(assignee_id, users_by_id) do
    case Map.get(users_by_id, assignee_id) do
      nil -> "ユーザー#{assignee_id}"
      user -> user.display_name || user.email || "ユーザー#{assignee_id}"
    end
  end

  defp count_by(items, attribute) do
    items
    |> Enum.frequencies_by(&Map.get(&1, attribute))
    |> Enum.map(fn {key, count} -> %{key: key, count: count} end)
    |> Enum.sort_by(fn row -> {-row.count, to_string(row.key)} end)
  end

  defp average_age_hours(_now, []), do: 0.0

  defp average_age_hours(now, tickets) do
    total = Enum.reduce(tickets, 0.0, &(age_hours(now, &1.inserted_at) + &2))
    Float.round(total / length(tickets), 1)
  end

  defp age_hours(now, inserted_at) do
    max(DateTime.diff(now, inserted_at, :second), 0) / 3600
  end

  defp period(opts) do
    {default_from, default_to} = default_period()
    {Keyword.get(opts, :from, default_from), Keyword.get(opts, :to, default_to)}
  end

  defp period_bounds(from, to) do
    from_dt = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    to_dt = to |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    {from_dt, to_dt}
  end

  defp escape(nil), do: ""
  defp escape(value) when is_binary(value), do: value |> String.replace("\"", "\"\"") |> then(&"\"#{&1}\"")
  defp escape(value), do: to_string(value)
end
