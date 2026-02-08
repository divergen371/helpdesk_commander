defmodule HelpdeskCommanderWeb.RemoteIpTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias HelpdeskCommanderWeb.RemoteIp, as: RemoteIpPlug

  setup do
    original = Application.get_env(:helpdesk_commander, :remote_ip, [])

    on_exit(fn ->
      Application.put_env(:helpdesk_commander, :remote_ip, original)
    end)

    :ok
  end

  test "returns conn unchanged when disabled" do
    Application.put_env(:helpdesk_commander, :remote_ip, enabled?: false, opts: [])

    conn = conn(:get, "/")
    result = RemoteIpPlug.call(conn, [])

    assert result.remote_ip == conn.remote_ip
  end

  test "uses remote_ip when enabled" do
    opts = RemoteIp.init(headers: ["x-forwarded-for"])
    Application.put_env(:helpdesk_commander, :remote_ip, enabled?: true, opts: opts)

    conn = put_req_header(conn(:get, "/"), "x-forwarded-for", "203.0.113.10")

    result = RemoteIpPlug.call(conn, [])

    assert result.remote_ip == {203, 0, 113, 10}
  end
end
