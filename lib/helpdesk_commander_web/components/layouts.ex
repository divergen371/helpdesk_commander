defmodule HelpdeskCommanderWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HelpdeskCommanderWeb, :html

  alias HelpdeskCommanderWeb.CurrentUser

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :any, default: nil, doc: "the signed-in user, when available"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <header class="navbar sticky top-0 z-30 border-b border-base-200 bg-base-100/95 px-4 backdrop-blur sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-3">
          <img src={~p"/images/logo.svg"} width="32" />
          <span class="text-sm font-semibold tracking-tight sm:text-base">Helpdesk Commander</span>
        </.link>
      </div>

      <div class="flex-none">
        <ul class="flex flex-wrap items-center justify-end gap-1 sm:gap-3">
          <%= if assigns[:current_user] do %>
            <li>
              <.link class="btn btn-ghost btn-sm" navigate={~p"/tickets"}>チケット</.link>
            </li>
            <%= if !CurrentUser.external?(assigns[:current_user]) do %>
              <li>
                <.link class="btn btn-ghost btn-sm" navigate={~p"/tasks"}>タスク</.link>
              </li>
              <li>
                <.link class="btn btn-ghost btn-sm" navigate={~p"/products"}>製品</.link>
              </li>
              <li>
                <.link class="btn btn-ghost btn-sm" navigate={~p"/relations"}>関係グラフ</.link>
              </li>
            <% end %>
            <li>
              <.link class="btn btn-ghost btn-sm" navigate={~p"/notifications"}>通知</.link>
            </li>
            <li class="hidden text-xs opacity-60 lg:block">
              {CurrentUser.display_label(assigns[:current_user])}
            </li>
            <li>
              <.link href={~p"/sign-out"} method="delete" class="btn btn-ghost btn-sm">
                ログアウト
              </.link>
            </li>
          <% else %>
            <li>
              <.link class="btn btn-primary btn-sm" navigate={~p"/sign-in"}>サインイン</.link>
            </li>
          <% end %>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-7xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        style="display: none;"
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        style="display: none;"
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  @spec theme_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
