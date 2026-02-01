defmodule HelpdeskCommanderWeb.TicketLive.Index do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    tickets =
      Ticket
      |> Ash.read!(domain: Helpdesk)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    {:ok,
     socket
     |> assign(:page_title, "Tickets")
     |> stream(:tickets, tickets)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Tickets
        <:subtitle>チケットの一覧</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets/new"}>
            <.icon name="hero-plus" class="size-4" /> 新規作成
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body p-0">
          <.table
            id="tickets"
            rows={@streams.tickets}
            row_item={fn {_id, ticket} -> ticket end}
          >
            <:col :let={ticket} label="ID">{ticket.public_id}</:col>
            <:col :let={ticket} label="Subject">{ticket.subject}</:col>
            <:col :let={ticket} label="Status">{ticket.status}</:col>
            <:col :let={ticket} label="Priority">{ticket.priority}</:col>
            <:action :let={ticket}>
              <.link class="link" navigate={~p"/tickets/#{ticket.public_id}"}>
                詳細
              </.link>
            </:action>
          </.table>
        </div>
      </div>

      <div class="mt-6">
        <.link class="link" navigate={~p"/"}>
          ← Home
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
