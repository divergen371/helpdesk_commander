defmodule HelpdeskCommander.Helpdesk.Changes.ComputePriority do
  @moduledoc """
  Impact × Urgency から優先度を算出して設定する。

  ルール:
  - `priority` を明示的に指定した場合は、その値と `priority_source = "manual"` を記録する。
  - `priority` が空（自動算出）の場合は算出表から決め、`priority_source = "auto"` にする。
  - `impact` / `urgency` が変わったときは再算出する。
  - 同じ操作で `priority` も指定された場合は、その明示値を優先し `"manual"` とする。
  """

  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk.Priority

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    priority = Ash.Changeset.get_attribute(changeset, :priority)
    impact = Ash.Changeset.get_attribute(changeset, :impact)
    urgency = Ash.Changeset.get_attribute(changeset, :urgency)
    computed = Priority.compute(impact, urgency)

    # 既定値で補完された priority は「明示指定」と区別する。
    priority_changed? =
      Ash.Changeset.changing_attribute?(changeset, :priority) and
        :priority not in changeset.defaults

    dimensions_changed? =
      Ash.Changeset.changing_attribute?(changeset, :impact) or
        Ash.Changeset.changing_attribute?(changeset, :urgency)

    cond do
      priority_changed? and priority in [nil, ""] ->
        apply_computed(changeset, computed)

      priority_changed? ->
        Ash.Changeset.change_attribute(changeset, :priority_source, "manual")

      dimensions_changed? and computed != nil ->
        apply_computed(changeset, computed)

      true ->
        changeset
    end
  end

  defp apply_computed(changeset, nil) do
    # 算出できないときは現在の優先度を維持し、自動扱いに戻す。
    changeset
    |> Ash.Changeset.change_attribute(:priority, current_priority(changeset))
    |> Ash.Changeset.change_attribute(:priority_source, "auto")
  end

  defp apply_computed(changeset, priority) do
    changeset
    |> Ash.Changeset.change_attribute(:priority, priority)
    |> Ash.Changeset.change_attribute(:priority_source, "auto")
  end

  defp current_priority(changeset) do
    case Ash.Changeset.get_attribute(changeset, :priority) do
      value when value in [nil, ""] ->
        Map.get(changeset.data, :priority) || "p3"

      value ->
        value
    end
  end
end
