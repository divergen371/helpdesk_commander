defmodule HelpdeskCommander.Attachments.ScannerTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Attachments.Scanner

  setup do
    original = [
      Application.get_env(:helpdesk_commander, :attachment_scan_command),
      Application.get_env(:helpdesk_commander, :attachment_scan_allow_skipped),
      Application.get_env(:helpdesk_commander, :attachment_scan_timeout_ms)
    ]

    on_exit(fn ->
      [command, allow_skipped, timeout] = original
      Application.put_env(:helpdesk_commander, :attachment_scan_command, command)
      Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, allow_skipped)
      Application.put_env(:helpdesk_commander, :attachment_scan_timeout_ms, timeout)
    end)

    :ok
  end

  defp scan_command(value), do: Application.put_env(:helpdesk_commander, :attachment_scan_command, value)

  defp scan_allow_skipped(value),
    do: Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, value)

  defp scan_timeout(value), do: Application.put_env(:helpdesk_commander, :attachment_scan_timeout_ms, value)

  test "returns skipped when the scanner is not configured and skipped is allowed" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)
    scan_allow_skipped(true)

    assert {:ok, :skipped, "scanner not configured"} = Scanner.scan("/tmp/whatever")
  end

  test "fails closed when the scanner is not configured and skipped is not allowed" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)
    scan_allow_skipped(false)

    assert {:error, :scanner_not_configured} = Scanner.scan("/tmp/whatever")
  end

  test "fails closed by default when the allow-skipped key is absent" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)
    Application.delete_env(:helpdesk_commander, :attachment_scan_allow_skipped)

    assert {:error, :scanner_not_configured} = Scanner.scan("/tmp/whatever")
  end

  test "rejects an invalid scanner configuration" do
    scan_command({:not_a_valid_config})
    scan_allow_skipped(true)

    assert {:error, :invalid_scanner_config} = Scanner.scan("/tmp/whatever")
  end

  test "times out a slow scanner" do
    scan_command({"sh", ["-c", "sleep 30"]})
    scan_timeout(50)

    assert {:error, :scan_timeout} = Scanner.scan("/tmp/whatever")
  end

  test "falls back to the default timeout for an invalid timeout value" do
    scan_command({"sh", ["-c", "exit 1"]})
    scan_timeout(:bad)

    assert {:ok, :infected, nil} = Scanner.scan("/tmp/whatever")
  end
end
