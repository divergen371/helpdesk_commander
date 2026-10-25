defmodule HelpdeskCommanderWeb.RelationGraphLive.Index do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Helpdesk.TicketGraph
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_user.company_id

    case TicketGraph.build_overview(company_id) do
      {:ok, graph} ->
        {:ok,
         socket
         |> assign(:page_title, "関係グラフ")
         |> assign(:graph, graph)}

      {:error, error} ->
        ErrorLog.log_error("relation_graph_live.index.load", error, company_id: company_id)

        {:ok,
         socket
         |> assign(:page_title, "関係グラフ")
         |> assign(:graph, %{nodes: [], edges: []})
         |> put_flash(:error, "関係グラフの取得に失敗しました")}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        関係グラフ
        <:subtitle>自社チケットの関連・再起票・重複・依存関係を俯瞰</:subtitle>
        <:actions>
          <.button navigate={~p"/tickets"}>
            チケット一覧
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center gap-4 text-xs">
            <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-red-600"></span>再起票</span>
            <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-violet-600"></span>重複</span>
            <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-blue-600"></span>依存</span>
            <span class="flex items-center gap-2"><span class="size-3 rounded-full bg-slate-500"></span>関連</span>
            <span class="opacity-60">ノードをクリックするとチケットを開きます</span>
          </div>

          <div
            :if={@graph.nodes != []}
            id="ticket-graph"
            phx-hook="TicketGraph"
            phx-update="ignore"
            data-graph={Jason.encode!(@graph)}
            style="height: 72vh; min-height: 32rem;"
            class="mt-4 w-full rounded-box bg-base-200/30"
          >
          </div>

          <div :if={@graph.nodes == []} class="p-12 text-center text-sm opacity-70">
            表示できるチケットがありません。
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
