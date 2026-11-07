# 夜間の品質メトリクス判定（HC-36）
#
#   TEST_COUNT=425 mix run --no-start priv/ci/quality_metrics.exs
#
# 現在のカバレッジ（cover/excoveralls.json）とテスト数を
# priv/ci/quality_baseline.json と比較し、許容を超える悪化があれば exit 1。
# 現在値を quality-metrics.json に書き出す（artifact 用）。

defmodule Quality.Metrics do
  @baseline_path "priv/ci/quality_baseline.json"
  @output_path "quality-metrics.json"
  @coverage_tolerance 0.3

  def run do
    with {:ok, current} <- current_metrics(),
         {:ok, baseline} <- baseline_metrics() do
      IO.puts("current:  #{inspect(current)}")
      IO.puts("baseline: #{inspect(baseline)}")

      write_output(current)
      warn_trend(current, baseline)

      if regressed?(current, baseline) do
        IO.puts("quality metrics: FAILED (regression beyond tolerance)")
        System.stop(1)
      else
        IO.puts("quality metrics: ok")
        System.stop(0)
      end
    else
      {:error, reason} ->
        IO.puts("quality metrics: FAILED (#{reason})")
        System.stop(1)
    end
  end

  defp current_metrics do
    with {:ok, coverage} <- coverage_from_file(),
         {:ok, tests} <- tests_from_env() do
      {:ok, %{coverage: round2(coverage), tests: tests}}
    end
  end

  defp coverage_from_file do
    path = System.get_env("COVERAGE_JSON") || "cover/excoveralls.json"

    with {:ok, body} <- File.read(path),
         {:ok, %{"source_files" => files}} when is_list(files) <- Jason.decode(body) do
      {hit, total} =
        Enum.reduce(files, {0, 0}, fn file, {hit, total} ->
          coverage = Map.get(file, "coverage", [])
          {hit + Enum.count(coverage, &(is_integer(&1) and &1 > 0)), total + Enum.count(coverage, &is_integer/1)}
        end)

      if total == 0, do: {:error, "no executable lines"}, else: {:ok, hit / total * 100}
    else
      _other -> {:error, "cannot read coverage JSON (#{path})"}
    end
  end

  defp tests_from_env do
    case System.get_env("TEST_COUNT") do
      nil -> {:ok, nil}
      value -> parse_integer(value)
    end
  end

  defp baseline_metrics do
    with {:ok, body} <- File.read(@baseline_path),
         {:ok, baseline} when is_map(baseline) <- Jason.decode(body) do
      {:ok,
       %{
         coverage: Map.get(baseline, "coverage", 80.0) * 1.0,
         tests: Map.get(baseline, "tests")
       }}
    else
      _other -> {:error, "cannot read baseline (#{@baseline_path})"}
    end
  end

  defp write_output(current) do
    payload =
      current
      |> Map.put(:checked_at, DateTime.utc_now() |> DateTime.to_iso8601())
      |> Jason.encode!(pretty: true)

    File.write!(@output_path, payload)
  end

  defp warn_trend(current, baseline) do
    if is_number(baseline.coverage) and current.coverage < baseline.coverage do
      IO.puts("  [warn] coverage decreased: #{baseline.coverage}% -> #{current.coverage}%")
    end

    if is_integer(baseline.tests) and is_integer(current.tests) and current.tests < baseline.tests do
      IO.puts("  [warn] test count decreased: #{baseline.tests} -> #{current.tests}")
    end
  end

  defp regressed?(current, baseline) do
    coverage_drop = baseline.coverage - current.coverage
    coverage_failed = coverage_drop > @coverage_tolerance

    tests_failed =
      is_integer(baseline.tests) and is_integer(current.tests) and current.tests < baseline.tests

    coverage_failed or tests_failed
  end

  defp round2(number), do: Float.round(number * 1.0, 2)

  defp parse_integer(value) do
    case Integer.parse(String.trim(value)) do
      {number, _rest} -> {:ok, number}
      :error -> {:error, "invalid TEST_COUNT: #{value}"}
    end
  end
end

Quality.Metrics.run()
