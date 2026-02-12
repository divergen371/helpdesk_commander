defmodule HelpdeskCommanderWeb.TicketLive.New do
  use HelpdeskCommanderWeb, :live_view
  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    {users, socket_after_users, users_loaded?} =
      case load_users(current_user, external_user?) do
        {:ok, users} ->
          {users, socket, true}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.new.load_users", error, user_id: current_user && current_user.id)

          {[], put_flash(socket, :error, "ユーザー一覧の取得に失敗しました"), false}
      end

    {products, socket_after_products, products_loaded?} =
      case load_products(current_user) do
        {:ok, products} ->
          {products, socket_after_users, true}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.new.load_products", error, user_id: current_user && current_user.id)

          {[], put_flash(socket_after_users, :error, "製品一覧の取得に失敗しました"), false}
      end

    form =
      Ticket
      |> AshPhoenix.Form.for_create(:create, domain: Helpdesk)
      |> to_form()

    show_sample_user? =
      users_loaded? and
        not external_user? and
        (users == [] or (current_user && length(users) == 1 && hd(users).id == current_user.id))

    {:ok,
     socket_after_products
     |> assign(:page_title, "New Ticket")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:users, users)
     |> assign(:products, products)
     |> assign(:products_loaded?, products_loaded?)
     |> assign(:show_sample_user?, show_sample_user?)
     |> assign(:form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", %{"form" => params}, socket) do
    params = maybe_put_requester_id(params, socket)
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, :form, form)}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"form" => params}, socket) do
    params = maybe_put_requester_id(params, socket)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, ticket} ->
        {:noreply,
         socket
         |> put_flash(:info, "チケットを作成しました")
         |> push_navigate(to: ~p"/tickets/#{ticket.public_id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> put_flash(:error, "入力内容を確認してください")
         |> assign(:form, form)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("create_sample_user", _params, socket) do
    email = "user+#{System.unique_integer([:positive])}@example.com"
    company_result = Accounts.Auth.default_company()

    case company_result do
      {:ok, company} ->
        changeset =
          Ash.Changeset.for_create(User, :create, %{
            email: email,
            display_name: "Sample User",
            company_id: company.id,
            status: "active"
          })

        case Ash.create(changeset, domain: Accounts) do
          {:ok, _user} ->
            {users, socket, users_loaded?} =
              case load_users(socket.assigns.current_user, socket.assigns.current_user_external?) do
                {:ok, users} ->
                  {users, socket, true}

                {:error, error} ->
                  ErrorLog.log_error("ticket_live.new.reload_users", error)

                  {socket.assigns.users, put_flash(socket, :error, "ユーザー一覧の取得に失敗しました"), false}
              end

            show_sample_user? =
              users_loaded? and
                not socket.assigns.current_user_external? and
                (users == [] or
                   (socket.assigns.current_user && length(users) == 1 &&
                      hd(users).id == socket.assigns.current_user.id))

            {:noreply,
             socket
             |> put_flash(:info, "サンプルユーザーを作成しました")
             |> assign(:users, users)
             |> assign(:show_sample_user?, show_sample_user?)}

          {:error, error} ->
            ErrorLog.log_error("ticket_live.new.create_sample_user", error)

            {:noreply, put_flash(socket, :error, "サンプルユーザーの作成に失敗しました")}
        end

      {:error, error} ->
        ErrorLog.log_error("ticket_live.new.default_company", error)

        {:noreply, put_flash(socket, :error, "会社情報の取得に失敗しました")}
    end
  end

  defp user_options(users) do
    Enum.map(users, fn user ->
      {user_label(user), user.id}
    end)
  end

  defp product_options(products) do
    Enum.map(products, fn product ->
      {product.name, product.id}
    end)
  end

  defp user_label(user), do: CurrentUser.display_label(user)

  defp maybe_put_requester_id(params, %{assigns: %{current_user_external?: true, current_user: %User{id: id}}}) do
    Map.put(params, "requester_id", id)
  end

  defp maybe_put_requester_id(params, _socket), do: params

  defp load_users(current_user, external_user?) do
    if external_user? and current_user do
      {:ok, [current_user]}
    else
      case Ash.read(User, domain: Accounts) do
        {:ok, users} ->
          {:ok,
           users
           |> Enum.reject(&(&1.role == "system" or &1.status in ~w(suspended anonymized)))
           |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp load_products(%User{company_id: company_id}) do
    case Product |> filter(company_id == ^company_id) |> Ash.read(domain: Helpdesk) do
      {:ok, products} -> {:ok, Enum.sort_by(products, & &1.name, :asc)}
      {:error, error} -> {:error, error}
    end
  end

  defp load_products(_current_user), do: {:ok, []}

  defp status_options do
    [
      {"new", "new"},
      {"triage", "triage"},
      {"in_progress", "in_progress"},
      {"waiting", "waiting"}
    ]
  end

  defp priority_options do
    [
      {"p1", "p1"},
      {"p2", "p2"},
      {"p3", "p3"},
      {"p4", "p4"}
    ]
  end

  defp type_options do
    [
      {"question", "question"},
      {"incident", "incident"},
      {"request", "request"}
    ]
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        新規チケット
        <:subtitle>まずは最小の項目で作成</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            一覧へ
          </.button>
        </:actions>
      </.header>

      <div :if={@show_sample_user?} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <p class="font-semibold">ユーザーが少ないためサンプル作成ができます</p>
          <p class="text-sm opacity-80">requester が必須なので、必要ならサンプルユーザーを追加してください。</p>
        </div>
        <div class="flex-1" />
        <.button type="button" phx-click="create_sample_user">
          サンプルユーザー作成
        </.button>
      </div>

      <div :if={@products_loaded? && @products == []} class="alert alert-warning">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <p class="font-semibold">製品が未登録です</p>
          <p class="text-sm opacity-80">チケット作成前に製品マスタを登録してください。</p>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@form} id="ticket-form" phx-change="validate" phx-submit="save">
            <.input field={@form[:subject]} label="件名" />
            <.input field={@form[:description]} type="textarea" label="詳細" />

            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <.input field={@form[:type]} type="select" label="種別" options={type_options()} />
              <.input field={@form[:status]} type="select" label="ステータス" options={status_options()} />
              <.input field={@form[:priority]} type="select" label="優先度" options={priority_options()} />
            </div>

            <.input
              field={@form[:product_id]}
              type="select"
              label="対象製品/サービス"
              prompt="選択してください"
              options={product_options(@products)}
              required
            />

            <%= if @current_user_external? do %>
              <div class="rounded-box border border-base-200 p-4 text-sm">
                <p class="text-xs uppercase tracking-wide opacity-60">依頼者</p>
                <p class="mt-1 font-medium">{user_label(@current_user)}</p>
              </div>
              <.input
                field={@form[:requester_id]}
                type="hidden"
                value={@current_user.id}
              />
            <% else %>
              <.input
                field={@form[:requester_id]}
                type="select"
                label="依頼者"
                prompt="選択してください"
                options={user_options(@users)}
                required
              />
            <% end %>

            <div class="mt-6 flex justify-end">
              <.button type="submit" variant="primary" disabled={@users == [] or @products == []}>
                作成
              </.button>
            </div>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
