defmodule HelpdeskCommander.Attachments.ScanMetadataTest do
  use ExUnit.Case, async: false

  alias HelpdeskCommander.Attachments.ScanMetadata

  setup do
    original = [
      Application.get_env(:helpdesk_commander, :attachment_scan_command),
      Application.get_env(:helpdesk_commander, :attachment_scan_version_command)
    ]

    on_exit(fn ->
      [command, version] = original
      Application.put_env(:helpdesk_commander, :attachment_scan_command, command)
      Application.put_env(:helpdesk_commander, :attachment_scan_version_command, version)
    end)

    :ok
  end

  test "parses clamscan version output" do
    output = "ClamAV 1.4.1/27480/Wed Nov  5 08:12:34 2026\n"

    assert %{engine: "ClamAV", version: "1.4.1", signature_at: signature_at} = ScanMetadata.parse(output)
    assert DateTime.to_iso8601(signature_at) == "2026-11-05T08:12:34Z"
  end

  test "returns empty metadata for unparseable output" do
    assert %{engine: nil, version: nil, signature_at: nil} = ScanMetadata.parse("something else")
    assert %{engine: nil, version: nil, signature_at: nil} = ScanMetadata.parse("")
  end

  test "collect runs the configured version command" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)

    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_version_command,
      {"sh", ["-c", "echo 'ClamAV 1.3.0/27000/Tue Jan  6 10:00:00 2026'"]}
    )

    assert %{engine: "ClamAV", version: "1.3.0", signature_at: signature_at} =
             ScanMetadata.collect()

    assert DateTime.to_iso8601(signature_at) == "2026-01-06T10:00:00Z"
  end

  test "collect returns empty when no version source is configured" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_command)
    Application.delete_env(:helpdesk_commander, :attachment_scan_version_command)

    assert %{engine: nil, version: nil, signature_at: nil} = ScanMetadata.collect()
  end

  test "collect returns empty when the version command fails" do
    Application.put_env(
      :helpdesk_commander,
      :attachment_scan_version_command,
      {"sh", ["-c", "exit 3"]}
    )

    assert %{engine: nil, version: nil, signature_at: nil} = ScanMetadata.collect()
  end
end
