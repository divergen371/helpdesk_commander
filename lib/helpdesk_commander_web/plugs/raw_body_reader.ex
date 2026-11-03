defmodule HelpdeskCommanderWeb.RawBodyReader do
  @moduledoc """
  生のリクエストボディを保持する Plug.Parsers の body_reader。

  Slack Events API の署名検証にはパース前のボディが必要なため、
  `conn.assigns.raw_body` に保存する。
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()}
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}
      {:more, body, conn} -> {:more, body, conn}
    end
  end
end
