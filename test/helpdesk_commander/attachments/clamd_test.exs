defmodule HelpdeskCommander.Attachments.ClamdTest do
  use ExUnit.Case, async: false

  alias HelpdeskCommander.Attachments.Clamd
  alias HelpdeskCommander.ClamdFakeServer

  @eicar "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"

  setup do
    original = Application.get_env(:helpdesk_commander, :attachment_scan_clamd)

    on_exit(fn ->
      Application.put_env(:helpdesk_commander, :attachment_scan_clamd, original)
    end)

    path = Path.join(System.tmp_dir!(), "clamd-#{System.unique_integer([:positive])}")
    File.write!(path, "benign content")
    on_exit(fn -> File.rm(path) end)

    {:ok, path: path}
  end

  defp configure(port, opts \\ []) do
    settings = [host: "127.0.0.1", port: port] ++ opts
    Application.put_env(:helpdesk_commander, :attachment_scan_clamd, settings)
    Clamd.default_config()
  end

  test "default_config is nil when clamd is not configured" do
    Application.delete_env(:helpdesk_commander, :attachment_scan_clamd)
    assert Clamd.default_config() == nil
    assert {:error, :clamd_not_configured} = Clamd.ping(nil)
  end

  test "default_config rejects malformed settings" do
    Application.put_env(:helpdesk_commander, :attachment_scan_clamd, port: 3310)
    assert Clamd.default_config() == nil
  end

  test "ping / version / reload speak the clamd protocol" do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :clean)
    config = configure(port)

    assert {:ok, "PONG"} = Clamd.ping(config)
    assert {:ok, version} = Clamd.version(config)
    assert version =~ "ClamAV 1.4.2/27608"
    assert {:ok, "RELOAD: succeeded"} = Clamd.reload(config)
  end

  test "scan_file reports clean for a benign file", %{path: path} do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :eicar)
    config = configure(port)

    assert {:ok, :clean, "stream: OK"} = Clamd.scan_file(path, config)
  end

  test "scan_file reports infected for the EICAR test file" do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :eicar)
    config = configure(port)

    path = Path.join(System.tmp_dir!(), "eicar-#{System.unique_integer([:positive])}")
    File.write!(path, @eicar)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, :infected, detection} = Clamd.scan_file(path, config)
    assert detection =~ "FOUND"
  end

  test "scan_file streams files larger than one chunk", %{path: path} do
    File.write!(path, :binary.copy("abcdefgh", 40_000))
    {:ok, port, _server} = ClamdFakeServer.start(mode: :clean)
    config = configure(port)

    assert {:ok, :clean, _note} = Clamd.scan_file(path, config)
  end

  test "fail closed on an ERROR response", %{path: path} do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :error)
    config = configure(port)

    assert {:error, {:clamd_error, reason}} = Clamd.scan_file(path, config)
    assert reason =~ "database problem"
  end

  test "fail closed when clamd does not answer", %{path: path} do
    {:ok, port, _server} = ClamdFakeServer.start(mode: :silent)
    config = configure(port, timeout_ms: 200)

    assert {:error, :clamd_timeout} = Clamd.scan_file(path, config)
  end

  test "fail closed when clamd is unreachable", %{path: path} do
    config = configure(1)

    assert {:error, {:clamd_connect, _reason}} = Clamd.scan_file(path, config)
  end
end
