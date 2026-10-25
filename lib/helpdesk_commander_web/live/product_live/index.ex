defmodule HelpdeskCommanderWeb.ProductLive.Index do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Products")
      |> assign(:form, new_product_form())
      |> reload_products()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, put_company_id(params, socket))

    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: put_company_id(params, socket)) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "製品を作成しました")
         |> assign(:form, new_product_form())
         |> reload_products()}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "入力内容を確認してください")
         |> assign(:form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_active", %{"id" => id}, socket) do
    case load_product(socket.assigns.current_user.company_id, id) do
      {:ok, %Product{} = product} ->
        case product
             |> Ash.Changeset.for_update(:update, %{active: !product.active})
             |> Ash.update(domain: Helpdesk) do
          {:ok, _product} ->
            {:noreply,
             socket
             |> put_flash(:info, if(product.active, do: "製品を無効化しました", else: "製品を有効化しました"))
             |> reload_products()}

          {:error, error} ->
            ErrorLog.log_error("product_live.index.toggle_active", error, product_id: product.id)
            {:noreply, put_flash(socket, :error, "製品の更新に失敗しました")}
        end

      _result ->
        {:noreply, put_flash(socket, :error, "製品が見つかりません")}
    end
  end

  defp new_product_form do
    Product
    |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
    |> to_form()
  end

  defp put_company_id(params, %{assigns: %{current_user: user}}) do
    Map.put(params, "company_id", user.company_id)
  end

  defp reload_products(socket) do
    query =
      Product
      |> filter(company_id == ^socket.assigns.current_user.company_id)
      |> sort(name: :asc)

    case Ash.read(query, domain: Helpdesk) do
      {:ok, products} ->
        assign(socket, :products, products)

      {:error, error} ->
        ErrorLog.log_error("product_live.index.load_products", error)
        put_flash(socket, :error, "製品一覧の取得に失敗しました")
    end
  end

  defp load_product(company_id, id) do
    case id |> to_string() |> Integer.parse() do
      {id, _rest} ->
        Product
        |> filter(id == ^id and company_id == ^company_id)
        |> Ash.read_one(domain: Helpdesk)

      :error ->
        {:error, :not_found}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        製品マスタ
        <:subtitle>チケット・問い合わせで選択する製品/サービス</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            チケット一覧
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <h3 class="font-semibold">製品を作成</h3>
          <.form for={@form} id="product-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label="名称" maxlength="100" required />
            <.input field={@form[:description]} type="textarea" label="説明" maxlength="1000" />

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary">作成</.button>
            </div>
          </.form>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body p-0">
          <.table id="products" rows={@products}>
            <:col :let={product} label="名称">{product.name}</:col>
            <:col :let={product} label="説明">{product.description || "-"}</:col>
            <:col :let={product} label="状態">
              <span class={["badge", if(product.active, do: "badge-success", else: "badge-ghost")]}>
                {if product.active, do: "有効", else: "無効"}
              </span>
            </:col>
            <:action :let={product}>
              <div class="flex items-center gap-3">
                <.link class="link" navigate={~p"/products/#{product.id}"}>
                  編集
                </.link>
                <.button
                  type="button"
                  phx-click="toggle_active"
                  phx-value-id={product.id}
                >
                  {if product.active, do: "無効化", else: "有効化"}
                </.button>
              </div>
            </:action>
          </.table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
