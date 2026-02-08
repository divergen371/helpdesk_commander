defmodule HelpdeskCommanderWeb.RemoteIp do
  @moduledoc """
  Optional RemoteIp plug wrapper that reads runtime config.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    config = Application.get_env(:helpdesk_commander, :remote_ip, [])

    if Keyword.get(config, :enabled?, false) do
      RemoteIp.call(conn, Keyword.get(config, :opts, []))
    else
      conn
    end
  end
end
