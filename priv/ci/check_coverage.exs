# カバレッジのラチェット判定（HC-33）
#
#   mix coveralls.json
#   mix run priv/ci/check_coverage.exs
#
# `cover/excoveralls.json` の合計カバレッジを、`priv/ci/coverage_baseline.txt` の
# 基準値（前回の下限）と比較する。基準を下回ると exit 1。
# 一時的な検証は `COVERAGE_BASELINE=99 mix run priv/ci/check_coverage.exs` で行える。
#
# 基準値の更新は、カバレッジが改善して安定した後にこのファイルを手で上げる（下げない）。

defmodule Quality.CoverageGate do
  @absolute_minimum 80.0

  def run do
    with {:ok, path} <- coverage_path(),
         {:ok, percentage} <- read_percentage(path) do
      baseline = baseline()
      threshold = max(@absolute_minimum, baseline)

      IO.puts(
        "coverage: #{format(percentage)}% (baseline #{format(baseline)}% / absolute minimum #{format(@absolute_minimum)}%)"
      )

      if percentage >= threshold do
        IO.puts("coverage gate: ok")
        System.stop(0)
      else
        IO.puts("coverage gate: FAILED (below #{format(threshold)}%)")
        System.stop(1)
      end
    else
      {:error, reason} ->
        IO.puts("coverage gate: FAILED (#{reason})")
        System.stop(1)
    end
  end

  defp coverage_path do
    path = System.get_env("COVERAGE_JSON") || "cover/excoveralls.json"

    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "coverage file not found: #{path} (run `mix coveralls.json` first)"}
    end
  end

  defp read_percentage(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"source_files" => files}} when is_list(files) <- Jason.decode(body) do
      covered =
        Enum.reduce(files, {0, 0}, fn file, {hit, total} ->
          coverage = Map.get(file, "coverage", [])

          covered = Enum.count(coverage, &(is_integer(&1) and &1 > 0))
          executable = Enum.count(coverage, &is_integer/1)
          {hit + covered, total + executable}
        end)

      case covered do
        {_hit, 0} -> {:error, "coverage data has no executable lines"}
        {hit, total} -> {:ok, hit / total * 100}
      end
    else
      _other -> {:error, "could not parse coverage JSON: #{path}"}
    end
  end

  defp baseline do
    case System.get_env("COVERAGE_BASELINE") do
      nil -> baseline_from_file()
      value -> parse_float(value, @absolute_minimum)
    end
  end

  defp baseline_from_file do
    path = "priv/ci/coverage_baseline.txt"

    case File.read(path) do
      {:ok, body} -> parse_float(body, @absolute_minimum)
      {:error, _reason} -> @absolute_minimum
    end
  end

  defp parse_float(value, fallback) do
    case Float.parse(String.trim(value)) do
      {number, _rest} -> number
      :error -> fallback
    end
  end

  defp format(number), do: :erlang.float_to_binary(number * 1.0, decimals: 2)
end

Quality.CoverageGate.run()
