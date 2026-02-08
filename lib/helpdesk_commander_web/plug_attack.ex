defmodule HelpdeskCommanderWeb.PlugAttack do
  @moduledoc """
  Request throttling and basic abuse protection.
  """

  use PlugAttack
  import Plug.Conn

  @storage {PlugAttack.Storage.Ets, HelpdeskCommanderWeb.PlugAttack.Storage}

  rule "allow local", conn do
    allow conn.remote_ip in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]
  end

  rule "throttle by ip", conn do
    throttle(conn.remote_ip,
      period: :timer.seconds(1),
      limit: 20,
      storage: @storage
    )
  end

  rule "login fail2ban", conn do
    if conn.method == "POST" and conn.path_info == ["users", "log_in"] do
      fail2ban({conn.remote_ip, "login"},
        period: :timer.minutes(5),
        limit: 20,
        ban_for: :timer.hours(1),
        storage: @storage
      )
    end
  end

  @impl PlugAttack
  def block_action(conn, {:throttle, _data}, _opts) do
    conn
    |> send_resp(:too_many_requests, "Too Many Requests\n")
    |> halt()
  end

  def block_action(conn, {:fail2ban, _data}, _opts) do
    conn
    |> send_resp(:too_many_requests, "Too Many Requests\n")
    |> halt()
  end
end
