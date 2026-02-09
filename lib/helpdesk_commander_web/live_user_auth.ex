defmodule HelpdeskCommanderWeb.LiveUserAuth do
  @moduledoc false

  use HelpdeskCommanderWeb, :verified_routes

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias HelpdeskCommanderWeb.CurrentUser

  @spec on_mount(:live_user_required, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:live_user_required, _params, session, socket) do
    case CurrentUser.fetch(session) do
      nil ->
        {:halt, redirect(socket, to: ~p"/sign-in")}

      user ->
        if CurrentUser.active?(user) do
          {:cont,
           socket
           |> assign(:current_user, user)
           |> assign(:current_user_external?, CurrentUser.external?(user))}
        else
          {:halt,
           socket
           |> put_flash(:error, "承認待ちのためログインできません")
           |> redirect(to: ~p"/sign-in")}
        end
    end
  end

  @spec on_mount(:admin_required, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:admin_required, _params, session, socket) do
    case CurrentUser.fetch(session) do
      nil ->
        {:halt, redirect(socket, to: ~p"/sign-in")}

      user ->
        if CurrentUser.active?(user) and CurrentUser.admin?(user) do
          {:cont,
           socket
           |> assign(:current_user, user)
           |> assign(:current_user_external?, CurrentUser.external?(user))}
        else
          {:halt,
           socket
           |> put_flash(:error, "アクセス権限がありません")
           |> redirect(to: ~p"/tickets")}
        end
    end
  end
end
