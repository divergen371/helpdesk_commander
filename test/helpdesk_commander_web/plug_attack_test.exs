defmodule HelpdeskCommanderWeb.PlugAttackTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  alias HelpdeskCommanderWeb.PlugAttack

  test "block_action throttles requests", %{conn: conn} do
    conn = PlugAttack.block_action(conn, {:throttle, %{limit: 1}}, [])

    assert conn.status == 429
    assert conn.resp_body == "Too Many Requests\n"
    assert conn.halted
  end

  test "block_action fail2ban blocks requests", %{conn: conn} do
    conn = PlugAttack.block_action(conn, {:fail2ban, %{ban_for: 1}}, [])

    assert conn.status == 429
    assert conn.resp_body == "Too Many Requests\n"
    assert conn.halted
  end
end
