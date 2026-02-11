defmodule HelpdeskCommanderWeb.AdminUserLive.Pending do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Auth
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {users, socket_after_users} =
      case pending_users() do
        {:ok, users} ->
          {users, socket}

        {:error, error} ->
          ErrorLog.log_error("admin_user_live.pending.load_users", error)

          {[], put_flash(socket, :error, "承認待ちユーザーの取得に失敗しました")}
      end

    {companies, socket_after_companies} =
      case company_map() do
        {:ok, companies} ->
          {companies, socket_after_users}

        {:error, error} ->
          ErrorLog.log_error("admin_user_live.pending.load_companies", error)

          {%{}, put_flash(socket_after_users, :error, "会社一覧の取得に失敗しました")}
      end

    socket = socket_after_companies

    {:ok,
     socket
     |> assign(:page_title, "Pending Users")
     |> assign(:pending_users, users)
     |> assign(:companies, companies)}
  end

  @impl Phoenix.LiveView
  def handle_event("approve", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.pending_users, fn user -> to_string(user.id) == id end)

    case user do
      nil ->
        {:noreply, put_flash(socket, :error, "対象ユーザーが見つかりません")}

      %User{} = user ->
        case Auth.approve_user(user) do
          {:ok, _user} ->
            {users, socket} =
              case pending_users() do
                {:ok, users} ->
                  {users, socket}

                {:error, error} ->
                  ErrorLog.log_error("admin_user_live.pending.reload_users", error)

                  {socket.assigns.pending_users, put_flash(socket, :error, "承認待ちユーザーの取得に失敗しました")}
              end

            {:noreply,
             socket
             |> put_flash(:info, "承認しました")
             |> assign(:pending_users, users)}

          {:error, error} ->
            ErrorLog.log_error("admin_user_live.pending.approve_user", error, user_id: user.id)
            {:noreply, put_flash(socket, :error, "承認に失敗しました")}
        end
    end
  end

  defp pending_users do
    query = filter(User, status == "pending")

    case Ash.read(query, domain: Accounts) do
      {:ok, users} ->
        {:ok, Enum.sort_by(users, & &1.inserted_at, {:asc, DateTime})}

      {:error, error} ->
        {:error, error}
    end
  end

  defp company_map do
    case Ash.read(Company, domain: Accounts) do
      {:ok, companies} ->
        {:ok, Map.new(companies, &{&1.id, &1})}

      {:error, error} ->
        {:error, error}
    end
  end

  defp company_name(companies, company_id) do
    case Map.get(companies, company_id) do
      %Company{name: name} -> name
      _company -> "-"
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        承認待ちユーザー
        <:subtitle>仮ユーザーの承認</:subtitle>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body p-0">
          <.table id="pending-users" rows={@pending_users}>
            <:col :let={user} label="会社">{company_name(@companies, user.company_id)}</:col>
            <:col :let={user} label="メール">{user.email}</:col>
            <:col :let={user} label="表示名">{user.display_name}</:col>
            <:col :let={user} label="ロール">{user.role}</:col>
            <:action :let={user}>
              <.button
                type="button"
                phx-click="approve"
                phx-value-id={user.id}
              >
                承認
              </.button>
            </:action>
          </.table>
        </div>
      </div>

      <div class="mt-6">
        <.link class="link" navigate={~p"/tickets"}>
          ← チケット一覧へ
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
