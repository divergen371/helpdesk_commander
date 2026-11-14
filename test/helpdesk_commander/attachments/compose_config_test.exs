defmodule HelpdeskCommander.Attachments.ComposeConfigTest do
  use ExUnit.Case, async: true

  @compose_path Path.expand("../../../docker-compose.yml", __DIR__)

  describe "ClamAV container memory limits" do
    test "clamd has at least 3g mem_limit for ConcurrentDatabaseReload peak" do
      mem_mb = extract_mem_limit_mb!("clamd")
      assert mem_mb >= 3 * 1024
    end

    test "clamav-db-updater has at least 2g mem_limit for freshclam database testing" do
      mem_mb = extract_mem_limit_mb!("clamav-db-updater")
      assert mem_mb >= 2 * 1024
    end
  end

  defp extract_mem_limit_mb!(service_name) do
    content = File.read!(@compose_path)

    pattern = ~r/^  #{Regex.escape(service_name)}:\n(?:(?:    .*|\s*)\n)*?    mem_limit:\s*(\S+)/m

    case Regex.run(pattern, content) do
      [_, raw] ->
        parse_mem_mb!(raw)

      nil ->
        flunk("mem_limit not found for service #{service_name} in docker-compose.yml")
    end
  end

  defp parse_mem_mb!(raw) do
    case Regex.run(~r/^(\d+)\s*([gm])b?$/i, String.trim(raw)) do
      [_, num, unit] ->
        value = String.to_integer(num)

        case String.downcase(unit) do
          "g" -> value * 1024
          "m" -> value
        end

      nil ->
        flunk("Unsupported mem_limit unit: #{raw}")
    end
  end
end
