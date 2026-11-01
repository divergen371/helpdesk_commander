defmodule HelpdeskCommander.Helpdesk.Priority do
  @moduledoc """
  Impact（影響）と Urgency（緊急度）から優先度を算出する。

  優先度は 4x4 の算出表で決める。どちらかが未設定、または想定外の値の場合は
  `nil` を返し、呼び出し側は既存の優先度を維持する。
  """

  @impacts ~w(widespread significant moderate minor)
  @urgencies ~w(critical high medium low)

  @matrix %{
    "widespread" => %{"critical" => "p1", "high" => "p1", "medium" => "p2", "low" => "p3"},
    "significant" => %{"critical" => "p1", "high" => "p2", "medium" => "p2", "low" => "p3"},
    "moderate" => %{"critical" => "p2", "high" => "p3", "medium" => "p3", "low" => "p4"},
    "minor" => %{"critical" => "p3", "high" => "p3", "medium" => "p4", "low" => "p4"}
  }

  @impact_labels %{
    "widespread" => "広範（全社・複数顧客）",
    "significant" => "大（部門・主要機能の停止）",
    "moderate" => "中（一部機能の低下）",
    "minor" => "小（軽微・回避可能）"
  }

  @urgency_labels %{
    "critical" => "即時（業務停止・本日中）",
    "high" => "高（24時間以内）",
    "medium" => "中（数日以内）",
    "low" => "低（急がない）"
  }

  @doc "有効な Impact の値一覧。"
  @spec impacts() :: [String.t()]
  def impacts, do: @impacts

  @doc "有効な Urgency の値一覧。"
  @spec urgencies() :: [String.t()]
  def urgencies, do: @urgencies

  @doc "Impact の値が有効か。"
  @spec impact?(term()) :: boolean()
  def impact?(value), do: value in @impacts

  @doc "Urgency の値が有効か。"
  @spec urgency?(term()) :: boolean()
  def urgency?(value), do: value in @urgencies

  @doc """
  Impact と Urgency から優先度を算出する。

  片方でも未設定・不正なら `nil`。
  """
  @spec compute(term(), term()) :: String.t() | nil
  def compute(impact, urgency) do
    get_in(@matrix, [impact, urgency])
  end

  @doc "Impact の表示ラベル。"
  @spec impact_label(term()) :: String.t()
  def impact_label(value), do: Map.get(@impact_labels, value, "-")

  @doc "Urgency の表示ラベル。"
  @spec urgency_label(term()) :: String.t()
  def urgency_label(value), do: Map.get(@urgency_labels, value, "-")

  @doc "Impact の選択肢。"
  @spec impact_options() :: [{String.t(), String.t()}]
  def impact_options do
    Enum.map(@impacts, &{impact_label(&1), &1})
  end

  @doc "Urgency の選択肢。"
  @spec urgency_options() :: [{String.t(), String.t()}]
  def urgency_options do
    Enum.map(@urgencies, &{urgency_label(&1), &1})
  end
end
