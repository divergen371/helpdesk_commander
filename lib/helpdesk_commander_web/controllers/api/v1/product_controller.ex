defmodule HelpdeskCommanderWeb.Api.V1.ProductController do
  @moduledoc """
  API v1 の製品一覧。
  """

  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Helpdesk

  action_fallback HelpdeskCommanderWeb.Api.FallbackController

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    user = conn.assigns.current_user
    active_only? = params["active_only"] in ["true", "1"]

    with {:ok, products} <- Helpdesk.list_products(user.company_id, active_only: active_only?) do
      json(conn, %{products: Enum.map(products, &product_json/1)})
    end
  end

  defp product_json(product) do
    %{
      id: product.id,
      name: product.name,
      active: Map.get(product, :active),
      company_id: product.company_id
    }
  end
end
