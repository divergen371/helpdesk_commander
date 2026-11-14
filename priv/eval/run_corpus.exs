# 検出品質の評価ハーネス（HC-26）
#
#   EVAL_SCANNER=stub mix run --no-start priv/eval/run_corpus.exs
#   EVAL_SCANNER=real ATTACHMENT_SCAN_CLAMD_HOST=127.0.0.1 mix run --no-start priv/eval/run_corpus.exs
#
# コーパス（priv/eval/corpus）を Scanner.scan/1 で検査し、検出率・誤検知率・
# スキャン時間を計測する。priv/eval/baseline.json の合格基準を下回ると exit 1。
# レポートは eval/detection_report.json に出力する。

defmodule Eval.Detection do
  alias HelpdeskCommander.Attachments.Clamd
  alias HelpdeskCommander.Attachments.Scanner

  @root "priv/eval"
  @report_path "eval/detection_report.json"

  def run do
    with :ok <- configure_scanner(),
         {:ok, samples} <- load_manifest(),
         {:ok, baseline} <- load_baseline() do
      results = Enum.map(samples, &scan/1)
      metrics = metrics(results)
      checks = checks(metrics, baseline)

      print_results(results, metrics, checks)
      write_report(results, metrics, checks, baseline, System.get_env("EVAL_SCANNER", "stub"))
      write_summary(metrics, checks)

      if Enum.all?(checks, & &1.ok?) do
        System.stop(0)
      else
        IO.puts("detection quality gate: FAILED")
        System.stop(1)
      end
    else
      {:error, reason} ->
        IO.puts("detection quality gate: FAILED (#{reason})")
        System.stop(1)
    end
  end

  defp configure_scanner do
    case System.get_env("EVAL_SCANNER", "stub") do
      "stub" ->
        script = Path.expand(Path.join(@root, "stub_scanner.sh"))
        Application.put_env(:helpdesk_commander, :attachment_scan_clamd, nil)
        Application.put_env(:helpdesk_commander, :attachment_scan_command, {script, []})
        Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, false)
        :ok

      "real" ->
        if Clamd.default_config() || Application.get_env(:helpdesk_commander, :attachment_scan_command) do
          Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, false)
          :ok
        else
          {:error, "real mode needs ATTACHMENT_SCAN_CLAMD_HOST or ATTACHMENT_SCAN_COMMAND"}
        end

      other ->
        {:error, "unknown EVAL_SCANNER=#{other} (use stub or real)"}
    end
  end

  defp load_manifest do
    path = Path.join(@root, "corpus/manifest.json")

    with {:ok, body} <- File.read(path),
         {:ok, %{"samples" => samples}} when is_list(samples) <- Jason.decode(body) do
      {:ok, samples}
    else
      _other -> {:error, "cannot read #{path}"}
    end
  end

  defp load_baseline do
    path = System.get_env("EVAL_BASELINE") || Path.join(@root, "baseline.json")

    with {:ok, body} <- File.read(path),
         {:ok, baseline} when is_map(baseline) <- Jason.decode(body) do
      {:ok, baseline}
    else
      _other -> {:error, "cannot read baseline #{path}"}
    end
  end

  defp scan(sample) do
    path = Path.join(@root, "corpus/" <> sample["path"])

    {microseconds, result} = :timer.tc(fn -> Scanner.scan(path) end)

    status =
      case result do
        {:ok, status, _note} -> status
        {:error, reason} -> {:error, reason}
      end

    %{
      path: sample["path"],
      label: sample["label"],
      status: status,
      duration_ms: microseconds / 1000
    }
  end

  defp metrics(results) do
    malicious = Enum.filter(results, &(&1.label == "malicious"))
    benign = Enum.filter(results, &(&1.label == "benign"))

    detected = Enum.count(malicious, &(&1.status == :infected))
    missed = Enum.count(malicious, &(&1.status in [:clean, :skipped]))
    false_positives = Enum.count(benign, &(&1.status == :infected))
    errors = Enum.count(results, &match?({:error, _}, &1.status))

    durations = Enum.map(results, & &1.duration_ms)

    %{
      total: length(results),
      malicious: length(malicious),
      benign: length(benign),
      detected: detected,
      missed: missed,
      false_positives: false_positives,
      errors: errors,
      detection_rate: pct(detected, length(malicious)),
      false_positive_rate: pct(false_positives, length(benign)),
      error_rate: pct(errors, length(results)),
      avg_ms: if(durations == [], do: 0.0, else: Enum.sum(durations) / length(durations)),
      p95_ms: percentile(durations, 0.95)
    }
  end

  defp checks(metrics, baseline) do
    [
      check("detection rate", metrics.detection_rate, baseline["min_detection_rate"], :min),
      check("false positive rate", metrics.false_positive_rate, baseline["max_false_positive_rate"], :max),
      check("error rate", metrics.error_rate, baseline["max_error_rate"], :max),
      check("p95 scan time (ms)", metrics.p95_ms, baseline["max_p95_ms"], :max)
    ]
  end

  defp check(name, actual, threshold, direction) do
    ok? =
      case direction do
        :min -> actual >= threshold
        :max -> actual <= threshold
      end

    %{name: name, actual: actual, threshold: threshold, direction: direction, ok?: ok?}
  end

  defp print_results(results, metrics, checks) do
    IO.puts("== corpus results ==")

    Enum.each(results, fn result ->
      IO.puts(
        "  #{String.pad_trailing(result.path, 26)} #{String.pad_trailing(result.label, 10)} " <>
          "#{format_status(result.status)} #{Float.round(result.duration_ms, 1)}ms"
      )
    end)

    IO.puts("")
    IO.puts("== metrics ==")
    IO.puts("  detection rate:      #{fmt(metrics.detection_rate)}%")
    IO.puts("  false positive rate: #{fmt(metrics.false_positive_rate)}%")
    IO.puts("  error rate:          #{fmt(metrics.error_rate)}%")
    IO.puts("  avg scan time:       #{fmt(metrics.avg_ms)}ms")
    IO.puts("  p95 scan time:       #{fmt(metrics.p95_ms)}ms")
    IO.puts("")

    Enum.each(checks, fn check ->
      status = if check.ok?, do: "ok  ", else: "FAIL"
      IO.puts("  [#{status}] #{check.name}: #{fmt(check.actual)} (threshold #{fmt(check.threshold)})")
    end)
  end

  defp write_report(results, metrics, checks, baseline, scanner) do
    report = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      scanner: scanner,
      metrics: metrics,
      baseline: baseline,
      checks: checks,
      results:
        Enum.map(results, fn result ->
          %{path: result.path, label: result.label, status: format_status(result.status), duration_ms: result.duration_ms}
        end)
    }

    path = Path.expand(@report_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(report, pretty: true))
    IO.puts("report: #{path}")
  end

  defp write_summary(metrics, checks) do
    if summary_path = System.get_env("GITHUB_STEP_SUMMARY") do
      rows =
        Enum.map_join(checks, "\n", fn check ->
          "| #{check.name} | #{fmt(check.actual)} | #{fmt(check.threshold)} | #{if check.ok?, do: "ok", else: "FAIL"} |"
        end)

      body = """
      ## Detection quality

      | metric | value |
      | --- | --- |
      | detection rate | #{fmt(metrics.detection_rate)}% |
      | false positive rate | #{fmt(metrics.false_positive_rate)}% |
      | error rate | #{fmt(metrics.error_rate)}% |
      | avg scan time | #{fmt(metrics.avg_ms)} ms |
      | p95 scan time | #{fmt(metrics.p95_ms)} ms |

      | check | actual | threshold | result |
      | --- | --- | --- | --- |
      #{rows}
      """

      File.write!(summary_path, body, [:append])
    end
  end

  defp format_status(status) when is_atom(status), do: to_string(status)
  defp format_status({:error, reason}), do: "error(#{inspect(reason)})"

  defp pct(_part, 0), do: 0.0
  defp pct(part, total), do: part / total * 100

  defp percentile([], _p), do: 0.0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    index = max(ceil(length(sorted) * p) - 1, 0)
    Enum.at(sorted, index)
  end

  defp fmt(number) when is_float(number), do: :erlang.float_to_binary(number, decimals: 2)
  defp fmt(number), do: to_string(number)
end

Eval.Detection.run()
