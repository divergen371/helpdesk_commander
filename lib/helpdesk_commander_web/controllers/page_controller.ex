defmodule HelpdeskCommanderWeb.PageController do
  use HelpdeskCommanderWeb, :controller

  @spec home(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def home(conn, _params) do
    render(conn, :home)
  end
end
