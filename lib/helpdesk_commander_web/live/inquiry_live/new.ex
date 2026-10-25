defmodule HelpdeskCommanderWeb.InquiryLive.New do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommanderWeb.CurrentUser
  alias HelpdeskCommanderWeb.FormOptions

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    {users, socket_after_users, users_loaded?} =
      case FormOptions.load_users(current_user, external_user?) do
        {:ok, users} ->
          {users, socket, true}

        {:error, error} ->
          ErrorLog.log_error("inquiry_live.new.load_users", error, user_id: CurrentUser.id(current_user))

          {[], put_flash(socket, :error, "ユーザー一覧の取得に失敗しました"), false}
      end

    {products, socket_after_products, products_loaded?} =
      case FormOptions.load_products(current_user) do
        {:ok, products} ->
          {products, socket_after_users, true}

        {:error, error} ->
          ErrorLog.log_error("inquiry_live.new.load_products", error, user_id: CurrentUser.id(current_user))

          {[], put_flash(socket_after_users, :error, "製品一覧の取得に失敗しました"), false}
      end

    form =
      Inquiry
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form()

    {:ok,
     socket_after_products
     |> assign(:page_title, "New Inquiry")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:users, users)
     |> assign(:products, products)
     |> assign(:users_loaded?, users_loaded?)
     |> assign(:products_loaded?, products_loaded?)
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, force_requester(params, socket))

    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    case prepare_save_params(params, socket) do
      {:ok, params} ->
        submit_inquiry(socket, params)

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp submit_inquiry(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, inquiry} ->
        case Ash.load(inquiry, [:ticket], domain: Helpdesk) do
          {:ok, %Inquiry{ticket: %Ticket{public_id: public_id}}} ->
            {:noreply,
             socket
             |> put_flash(:info, "問い合わせを受け付けました")
             |> push_navigate(to: ~p"/tickets/#{public_id}")}

          {:error, error} ->
            ErrorLog.log_error("inquiry_live.new.load_ticket", error, inquiry_id: inquiry.id)

            {:noreply, put_flash(socket, :error, "チケットの取得に失敗しました")}
        end

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "入力内容を確認してください")
         |> assign(:form, form)}
    end
  end

  defp prepare_save_params(params, socket) do
    params =
      params
      |> Map.drop(["company_id"])
      |> Map.put("source", "web")
      |> force_requester(socket)

    if socket.assigns.current_user_external? do
      {:ok, params}
    else
      ensure_requester_in_company(params, socket.assigns.current_user)
    end
  end

  defp ensure_requester_in_company(%{"requester_id" => requester_id} = params, current_user) do
    with {id, _rest} <-
           requester_id |> to_string() |> Integer.parse(),
         {:ok, %User{company_id: company_id}}
         when company_id == current_user.company_id <-
           Ash.get(User, %{id: id}, domain: Accounts) do
      {:ok, params}
    else
      :error -> {:error, "依頼者を選択してください"}
      _result -> {:error, "依頼者が見つかりません"}
    end
  end

  defp ensure_requester_in_company(_params, _current_user) do
    {:error, "依頼者を選択してください"}
  end

  defp force_requester(params, %{assigns: %{current_user_external?: true, current_user: %User{id: id}}}) do
    Map.put(params, "requester_id", id)
  end

  defp force_requester(params, _socket), do: params

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        問い合わせ
        <:subtitle>送信するとチケットが自動生成されます</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div :if={@products_loaded? && @products == []} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <p class="font-semibold">製品が未登録です</p>
          <p class="text-sm opacity-80">問い合わせを送信する前に製品マスタを登録してください。</p>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@form} id="inquiry-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:subject]} label="件名" maxlength="200" required />
            <.input field={@form[:body]} type="textarea" label="問い合わせ内容" required />

            <.input
              field={@form[:product_id]}
              type="select"
              label="対象製品/サービス"
              prompt="選択してください"
              options={FormOptions.product_options(@products)}
              required
            />

            <%= if @current_user_external? do %>
              <div class="rounded-box border border-base-200 p-4 text-sm">
                <p class="text-xs uppercase tracking-wide opacity-60">依頼者</p>
                <p class="mt-1 font-medium">{CurrentUser.display_label(@current_user)}</p>
              </div>
              <.input field={@form[:requester_id]} type="hidden" value={@current_user.id} />
            <% else %>
              <.input
                field={@form[:requester_id]}
                type="select"
                label="依頼者"
                prompt="選択してください"
                options={FormOptions.user_options(@users)}
                required
              />
            <% end %>

            <div class="mt-6 flex justify-end">
              <.button
                type="submit"
                variant="primary"
                disabled={@products == [] or (@users_loaded? and @users == [])}
              >
                問い合わせを送信
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
