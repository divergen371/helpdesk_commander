defmodule HelpdeskCommanderWeb.NotificationLive.Index do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Helpdesk.Notifications
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Notifications")
      |> stream(:notifications, [])
      |> reload_notifications()

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("mark_read", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {notification_id, _rest} ->
        case Notifications.mark_read(socket.assigns.current_user, notification_id) do
          {:ok, _notification} ->
            {:noreply,
             socket
             |> put_flash(:info, "通知を既読にしました")
             |> reload_notifications()}

          {:error, error} ->
            ErrorLog.log_error("notification_live.index.mark_read", error, notification_id: id)

            {:noreply, put_flash(socket, :error, "通知の更新に失敗しました")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "通知が見つかりません")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("mark_all_read", _params, socket) do
    case Notifications.mark_all_read(socket.assigns.current_user) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{count} 件の通知を既読にしました")
         |> reload_notifications()}

      {:error, error} ->
        ErrorLog.log_error("notification_live.index.mark_all_read", error)

        {:noreply, put_flash(socket, :error, "通知の更新に失敗しました")}
    end
  end

  defp reload_notifications(socket) do
    case Notifications.list_for(socket.assigns.current_user) do
      {:ok, notifications} ->
        unread_count = Enum.count(notifications, &is_nil(&1.read_at))

        socket
        |> assign(:unread_count, unread_count)
        |> stream(:notifications, notifications, reset: true)

      {:error, error} ->
        ErrorLog.log_error("notification_live.index.load_notifications", error)

        socket
        |> assign(:unread_count, 0)
        |> put_flash(:error, "通知の取得に失敗しました")
        |> stream(:notifications, [], reset: true)
    end
  end

  defp format_dt(nil), do: "-"

  defp format_dt(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        通知
        <:subtitle>{@unread_count} 件の未読通知</:subtitle>
        <:actions>
          <.button
            :if={@unread_count > 0}
            type="button"
            phx-click="mark_all_read"
          >
            すべて既読にする
          </.button>
          <.button navigate={~p"/tickets"}>
            チケット一覧
          </.button>
        </:actions>
      </.header>

      <div id="notifications" phx-update="stream" class="space-y-3">
        <div
          id="notifications-empty"
          class="hidden only:block rounded-2xl border border-base-200 bg-base-100 p-6 text-sm opacity-70"
        >
          通知はまだありません。
        </div>

        <div
          :for={{id, notification} <- @streams.notifications}
          id={id}
          class={[
            "rounded-2xl border bg-base-100 p-4",
            is_nil(notification.read_at) && "border-primary/40 bg-base-200/30"
          ]}
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex items-center gap-2">
              <span :if={is_nil(notification.read_at)} class="badge badge-primary badge-sm">
                未読
              </span>
              <span class="text-xs opacity-60">{notification.notification_type}</span>
            </div>
            <span class="text-xs opacity-60">{format_dt(notification.inserted_at)}</span>
          </div>

          <h3 class="mt-2 font-semibold">{notification.title}</h3>
          <p class="mt-1 whitespace-pre-wrap text-sm opacity-80">{notification.body}</p>

          <div class="mt-4 flex flex-wrap items-center justify-end gap-3 text-sm">
            <.link
              class="link"
              navigate={~p"/tickets/#{notification.ticket.public_id}"}
            >
              チケットを開く
            </.link>
            <.button
              :if={is_nil(notification.read_at)}
              type="button"
              phx-click="mark_read"
              phx-value-id={notification.id}
            >
              既読にする
            </.button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
