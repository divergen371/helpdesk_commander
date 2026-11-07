defmodule HelpdeskCommander.Attachments.ClamavTest do
  use ExUnit.Case, async: false

  alias HelpdeskCommander.Attachments.Clamav

  setup do
    original = Application.get_env(:helpdesk_commander, :attachment_scan_clamav)
    on_exit(fn -> Application.put_env(:helpdesk_commander, :attachment_scan_clamav, original) end)
    :ok
  end

  test "builds the deep-scan args with the ClamAV default limits" do
    args = Clamav.args()

    for flag <- [
          "--scan-archive=yes",
          "--scan-pdf=yes",
          "--scan-ole2=yes",
          "--scan-html=yes",
          "--max-scansize=100M",
          "--max-filesize=25M",
          "--max-recursion=16",
          "--max-files=10000",
          "--alert-encrypted=yes",
          "--alert-macros=yes"
        ] do
      assert flag in args
    end

    assert length(args) == 10
  end

  test "accepts limit overrides from config" do
    Application.put_env(:helpdesk_commander, :attachment_scan_clamav,
      max_filesize: "10M",
      max_recursion: 3
    )

    args = Clamav.args()

    assert "--max-filesize=10M" in args
    assert "--max-recursion=3" in args
    refute "--max-filesize=25M" in args
    assert "--max-scansize=100M" in args
  end

  test "attaches deep-scan args only to clamscan" do
    assert {"clamscan", args} = Clamav.scan_command("clamscan")
    assert "--alert-encrypted=yes" in args

    assert {"/usr/local/bin/clamscan", args} = Clamav.scan_command("/usr/local/bin/clamscan")
    assert "--alert-macros=yes" in args

    assert "/usr/local/bin/custom-wrapper" = Clamav.scan_command("/usr/local/bin/custom-wrapper")
    assert "clamdscan" = Clamav.scan_command("clamdscan")
  end
end
