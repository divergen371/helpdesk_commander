defmodule HelpdeskCommanderWeb.AdminUserLive.Pending do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Auth
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    users = pending_users()
    companies = company_map()

    {:ok,
     socket
     |> assign(:page_title, "Pending Users")
     |> assign(:pending_users, users)
     |> assign(:companies, companies)}
  end

  @impl Phoenix.LiveView
  def handle_event("approve", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.pending_users, fn user -> to_string(user.id) == id end)

    case user && Auth.approve_user(user) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "承認しました")
         |> assign(:pending_users, pending_users())}

      _result ->
        {:noreply, put_flash(socket, :error, "承認に失敗しました")}
    end
  end

  defp pending_users do
    User
    |> filter(status == "pending")
    |> Ash.read!(domain: Accounts)
    |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
  end

  defp company_map do
    Company
    |> Ash.read!(domain: Accounts)
    |> Map.new(&{&1.id, &1})
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
