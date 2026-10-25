defmodule HelpdeskCommanderWeb.ProductLive.Show do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case load_product(socket.assigns.current_user.company_id, id) do
      {:ok, %Product{} = product} ->
        {:ok,
         socket
         |> assign(:page_title, "Product #{product.name}")
         |> assign(:product, product)
         |> assign(:form, edit_form(product))}

      _result ->
        {:ok,
         socket
         |> put_flash(:error, "製品が見つかりません")
         |> push_navigate(to: ~p"/products")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "製品を更新しました")
         |> assign(:product, product)
         |> assign(:form, edit_form(product))}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "製品の更新に失敗しました")
         |> assign(:form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("toggle_active", _params, socket) do
    product = socket.assigns.product

    case product
         |> Ash.Changeset.for_update(:update, %{active: !product.active})
         |> Ash.update(domain: Helpdesk) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, if(product.active, do: "製品を有効化しました", else: "製品を無効化しました"))
         |> assign(:product, product)
         |> assign(:form, edit_form(product))}

      {:error, error} ->
        ErrorLog.log_error("product_live.show.toggle_active", error, product_id: product.id)
        {:noreply, put_flash(socket, :error, "製品の更新に失敗しました")}
    end
  end

  defp edit_form(product) do
    product
    |> AshPhoenix.Form.for_update(:update, domain: Helpdesk)
    |> to_form()
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
        {@product.name}
        <:subtitle>製品マスタの編集</:subtitle>
        <:actions>
          <.button navigate={~p"/products"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <span class="text-sm opacity-70">状態</span>
              <div class="mt-1">
                <span class={["badge", if(@product.active, do: "badge-success", else: "badge-ghost")]}>
                  {if @product.active, do: "有効", else: "無効"}
                </span>
              </div>
            </div>
            <.button type="button" phx-click="toggle_active">
              {if @product.active, do: "無効化", else: "有効化"}
            </.button>
          </div>

          <.form for={@form} id="product-edit-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label="名称" maxlength="100" required />
            <.input field={@form[:description]} type="textarea" label="説明" maxlength="1000" />

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary">保存</.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
