defmodule HelpdeskCommanderWeb.PageController do
  use HelpdeskCommanderWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
