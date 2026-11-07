defmodule HelpdeskCommander.Attachments.ScannerTest do
  use HelpdeskCommander.DataCase, async: false

  alias HelpdeskCommander.Attachments.Scanner

  alias HelpdeskCommander.ClamdFakeServer

  setup do
    original = [
      Application.get_env(:helpdesk_commander, :attachment_scan_command),
      Application.get_env(:helpdesk_commander, :attachment_scan_allow_skipped),
      Application.get_env(:helpdesk_commander, :attachment_scan_timeout_ms),
      Application.get_env(:helpdesk_commander, :attachment_scan_clamd)
    ]

    on_exit(fn ->
      [command, allow_skipped, timeout, clamd] = original
      Application.put_env(:helpdesk_commander, :attachment_scan_command, command)
      Application.put_env(:helpdesk_commander, :attachment_scan_allow_skipped, allow_skipped)
      Application.put_env(:helpdesk_commander, :attachment_scan_timeout_ms, timeout)
      Application.put_env(:helpdesk_commander, :attachment_scan_clamd, clamd)
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

  test "the clamd sidecar takes precedence over the scanner command" do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :infected)
    path = temp_path("clamd-priority")

    scan_command({"sh", ["-c", "exit 0"]})
    Application.put_env(:helpdesk_commander, :attachment_scan_clamd, host: "127.0.0.1", port: port)

    assert {:ok, :infected, detection} = Scanner.scan(path)
    assert detection =~ "FOUND"
  end

  test "clamd connection failures stay fail-closed" do
    path = temp_path("clamd-unreachable")
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)

    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_clamd,
      host: "127.0.0.1",
      port: 1,
      timeout_ms: 200
    )

    assert {:error, {:clamd_connect, _reason}} = Scanner.scan(path)
  end

  defp temp_path(label) do
    path = Path.join(System.tmp_dir!(), "scanner-#{label}-#{System.unique_integer([:positive])}")
    File.write!(path, "content")
    on_exit(fn -> File.rm(path) end)
    path
  end
end
