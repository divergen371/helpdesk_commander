# 依存関係の監査ゲート（HC-34）
#
#   mix run --no-start priv/ci/check_audit.exs
#
# `mix hex.audit` の retired / advisory を allowlist（priv/ci/audit_allowlist.txt）と
# 照合する。allowlist に無い検出、期限切れの entry、期限の近い entry を報告する。
# 未許可の検出があれば exit 1。

defmodule Quality.AuditGate do
  @allowlist_path "priv/ci/audit_allowlist.txt"
  @warn_days 30

  def run do
    {output, status} = run_hex_audit()
    findings = parse_findings(output)
    entries = load_allowlist()

    IO.puts("== dependency audit ==")
    IO.puts("findings: #{length(findings)} / allowlist entries: #{length(entries)}")

    results = Enum.map(findings, &classify(&1, entries))

    Enum.each(results, fn {finding, verdict} ->
      label =
        case verdict do
          :allowed -> "allowed"
          {:expired, entry} -> "EXPIRED allowlist (review_by #{entry.review_by})"
          :unlisted -> "UNLISTED"
        end

      IO.puts("  [#{label}] #{finding.package} #{finding.version} #{finding.identifier}")
    end)

    warn_expiring(entries)
    warn_stale(entries, findings)

    _ = status
    failed? = Enum.any?(results, fn {_finding, verdict} -> verdict != :allowed end)

    if failed? do
      IO.puts("audit gate: FAILED")
      System.stop(1)
    else
      IO.puts("audit gate: ok")
      System.stop(0)
    end
  end

  defp run_hex_audit do
    System.cmd("mix", ["hex.audit"], stderr_to_stdout: true)
  end

  defp parse_findings(output) do
    output
    |> String.split("\n")
    |> Enum.flat_map(&parse_line/1)
    |> Enum.uniq_by(&{&1.package, &1.version, &1.identifier})
  end

  # "  ash_sql 0.8.3 - (security) ..."  /  "  bandit 1.13.1 - EEF-CVE-... (HIGH)"
  defp parse_line(line) do
    case Regex.run(~r/^  ([a-z0-9_]+) ([0-9][^ ]*) - (.+)$/, String.trim_trailing(line)) do
      [_, package, version, rest] ->
        identifier =
          case Regex.run(~r/(EEF-[A-Z0-9-]+)/, rest) do
            [_, id] -> id
            _ -> "retired:#{package}@#{version}"
          end

        [%{package: package, version: version, identifier: identifier}]

      _other ->
        []
    end
  end

  defp load_allowlist do
    case File.read(@allowlist_path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(String.trim(&1), "#"))
        |> Enum.flat_map(&parse_entry/1)

      {:error, _reason} ->
        []
    end
  end

  defp parse_entry(line) do
    case String.split(line, "|", trim: true) do
      [package, version, identifier, reason, review_by] ->
        [
          %{
            package: String.trim(package),
            version: String.trim(version),
            identifier: String.trim(identifier),
            reason: String.trim(reason),
            review_by: String.trim(review_by)
          }
        ]

      _other ->
        []
    end
  end

  defp classify(finding, entries) do
    case Enum.find(entries, &matches?(&1, finding)) do
      nil ->
        {finding, :unlisted}

      entry ->
        if expired?(entry), do: {finding, {:expired, entry}}, else: {finding, :allowed}
    end
  end

  defp matches?(entry, finding) do
    entry.package == finding.package and
      (entry.version == "*" or entry.version == finding.version) and
      entry.identifier == finding.identifier
  end

  defp expired?(entry) do
    case Date.from_iso8601(entry.review_by) do
      {:ok, date} -> Date.compare(date, Date.utc_today()) == :lt
      {:error, _reason} -> false
    end
  end

  defp warn_expiring(entries) do
    Enum.each(entries, fn entry ->
      case Date.from_iso8601(entry.review_by) do
        {:ok, date} ->
          days = Date.diff(date, Date.utc_today())

          if days >= 0 and days <= @warn_days do
            IO.puts("  [warn] allowlist expires in #{days} days: #{entry.identifier}")
          end

        {:error, _reason} ->
          IO.puts("  [warn] invalid review_by date: #{entry.identifier} (#{entry.review_by})")
      end
    end)
  end

  defp warn_stale(entries, findings) do
    Enum.each(entries, fn entry ->
      if Enum.all?(findings, &(not matches?(entry, &1))) do
        IO.puts("  [warn] allowlist entry no longer matches any finding: #{entry.identifier}")
      end
    end)
  end
end

Quality.AuditGate.run()
