defmodule HelpdeskCommanderWeb.TicketLive.Index do
  use HelpdeskCommanderWeb, :live_view

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommanderWeb.CurrentUser
  alias HelpdeskCommanderWeb.FormOptions

  @page_size 20
  @statuses ~w(new triage in_progress waiting resolved verified closed)
  @priorities ~w(p1 p2 p3 p4)
  @types ~w(question incident request)
  @sorts ~w(newest oldest priority status)

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)
    external_user? = CurrentUser.external?(current_user)

    {assignees, socket} =
      case FormOptions.load_internal_users(current_user) do
        {:ok, assignees} ->
          {assignees, socket}

        {:error, error} ->
          ErrorLog.log_error("ticket_live.index.load_assignees", error)

          {[], put_flash(socket, :error, "担当者一覧の取得に失敗しました")}
      end

    {:ok,
     socket
     |> assign(:page_title, "Tickets")
     |> assign(:current_user, current_user)
     |> assign(:current_user_external?, external_user?)
     |> assign(:assignees, assignees)
     |> assign(:page_size, @page_size)
     |> assign(:filter_form, filter_form(default_filters()))
     |> stream(:tickets, [])}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)
    page = parse_page(params)

    case load_tickets(socket.assigns.current_user, socket.assigns.current_user_external?, filters, page) do
      {:ok, %{tickets: tickets, total_count: total_count, has_next?: has_next?}} ->
        {:noreply,
         socket
         |> assign(:filters, filters)
         |> assign(:filter_form, filter_form(filters))
         |> assign(:page, page)
         |> assign(:total_count, total_count)
         |> assign(:total_pages, total_pages(total_count))
         |> assign(:has_next?, has_next?)
         |> stream(:tickets, tickets, reset: true)}

      {:error, error} ->
        ErrorLog.log_error("ticket_live.index.load_tickets", error,
          user_id: CurrentUser.id(socket.assigns.current_user)
        )

        {:noreply,
         socket
         |> put_flash(:error, "チケットの取得に失敗しました")
         |> assign(:filters, filters)
         |> assign(:filter_form, filter_form(filters))
         |> assign(:page, page)
         |> assign(:total_count, 0)
         |> assign(:total_pages, 1)
         |> assign(:has_next?, false)
         |> stream(:tickets, [], reset: true)}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("filter", %{"filters" => params}, socket) do
    params =
      params
      |> reject_blank()
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/tickets?#{params}")}
  end

  defp load_tickets(%User{company_id: company_id} = user, external_user?, filters, page) do
    query =
      Ticket
      |> filter(company_id == ^company_id or visibility_scope == "global")
      |> maybe_filter_for_external(external_user?, user)
      |> apply_filters(filters)
      |> sort_tickets(filters[:sort])

    offset = (page - 1) * @page_size

    case Ash.read(query, domain: Helpdesk, page: [limit: @page_size, offset: offset, count: true]) do
      {:ok, %Ash.Page.Offset{results: tickets, count: total_count, more?: has_next?}} ->
        case Ash.load(tickets, [:product, :assignee], domain: Helpdesk) do
          {:ok, tickets} ->
            {:ok, %{tickets: tickets, total_count: total_count, has_next?: has_next?}}

          {:error, error} ->
            {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp load_tickets(_current_user, _external_user?, _filters, _page) do
    {:ok, %{tickets: [], total_count: 0, has_next?: false}}
  end

  defp maybe_filter_for_external(query, true, %User{id: requester_id}) do
    filter(query, requester_id == ^requester_id)
  end

  defp maybe_filter_for_external(query, _external, _user), do: query

  defp apply_filters(query, filters) do
    query
    |> filter_status(filters[:status])
    |> filter_priority(filters[:priority])
    |> filter_type(filters[:type])
    |> filter_assignee(filters[:assignee_id])
  end

  defp filter_status(query, value) when value in @statuses, do: filter(query, status == ^value)
  defp filter_status(query, _value), do: query

  defp filter_priority(query, value) when value in @priorities,
    do: filter(query, priority == ^value)

  defp filter_priority(query, _value), do: query

  defp filter_type(query, value) when value in @types, do: filter(query, type == ^value)
  defp filter_type(query, _value), do: query

  defp filter_assignee(query, "unassigned"), do: filter(query, is_nil(assignee_id))

  defp filter_assignee(query, value) when is_binary(value) do
    case Integer.parse(value) do
      {assignee_id, _rest} -> filter(query, assignee_id == ^assignee_id)
      :error -> query
    end
  end

  defp filter_assignee(query, _value), do: query

  defp sort_tickets(query, "oldest"), do: sort(query, inserted_at: :asc)
  defp sort_tickets(query, "priority"), do: sort(query, priority: :asc, inserted_at: :desc)
  defp sort_tickets(query, "status"), do: sort(query, status: :asc, inserted_at: :desc)
  defp sort_tickets(query, _sort), do: sort(query, inserted_at: :desc)

  defp default_filters do
    %{status: nil, priority: nil, type: nil, assignee_id: nil, sort: "newest"}
  end

  defp filter_form(filters) do
    params = Map.new(filters, fn {key, value} -> {to_string(key), value} end)
    to_form(params, as: "filters")
  end

  defp parse_filters(params) do
    %{
      status: allow(params["status"], @statuses),
      priority: allow(params["priority"], @priorities),
      type: allow(params["type"], @types),
      assignee_id: normalize_assignee(params["assignee_id"]),
      sort: allow(params["sort"], @sorts) || "newest"
    }
  end

  defp allow(value, allowed) do
    if value in allowed, do: value, else: nil
  end

  defp normalize_assignee("unassigned"), do: "unassigned"
  defp normalize_assignee(nil), do: nil
  defp normalize_assignee(""), do: nil

  defp normalize_assignee(value) do
    case Integer.parse(value) do
      {_id, _rest} -> value
      :error -> nil
    end
  end

  defp parse_page(params) do
    case params["page"] |> to_string() |> Integer.parse() do
      {page, _rest} when page > 0 -> page
      _result -> 1
    end
  end

  defp total_pages(0), do: 1
  defp total_pages(total_count), do: ceil(total_count / @page_size)

  defp reject_blank(params) do
    Enum.reject(params, fn {_key, value} -> value in [nil, ""] end)
  end

  defp page_path(filters, page) do
    params =
      filters
      |> Enum.reject(fn {key, value} ->
        (key == :sort and value == "newest") or value in [nil, ""]
      end)
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("page", to_string(page))

    ~p"/tickets?#{params}"
  end

  defp status_options do
    Enum.map(@statuses, &{&1, &1})
  end

  defp priority_options do
    Enum.map(@priorities, &{&1, &1})
  end

  defp type_options do
    Enum.map(@types, &{&1, &1})
  end

  defp sort_options do
    [
      {"新しい順", "newest"},
      {"古い順", "oldest"},
      {"優先度順", "priority"},
      {"ステータス順", "status"}
    ]
  end

  defp assignee_options(assignees) do
    [{"未割り当て", "unassigned"} | FormOptions.user_options(assignees)]
  end

  defp assignee_label(nil), do: "-"
  defp assignee_label(%User{} = user), do: CurrentUser.display_label(user)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Tickets
        <:subtitle>チケットの一覧</:subtitle>
        <:actions>
          <.button navigate={~p"/inquiries/new"} variant="primary">
            <.icon name="hero-chat-bubble-left-right" class="size-4" /> 問い合わせ
          </.button>
          <.button navigate={~p"/tickets/new"}>
            <.icon name="hero-plus" class="size-4" /> 新規作成
          </.button>
        </:actions>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@filter_form} id="ticket-filters" phx-change="filter">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
              <.input
                field={@filter_form[:status]}
                type="select"
                label="ステータス"
                prompt="すべて"
                options={status_options()}
              />
              <.input
                field={@filter_form[:priority]}
                type="select"
                label="優先度"
                prompt="すべて"
                options={priority_options()}
              />
              <.input
                field={@filter_form[:type]}
                type="select"
                label="種別"
                prompt="すべて"
                options={type_options()}
              />
              <.input
                field={@filter_form[:assignee_id]}
                type="select"
                label="担当者"
                prompt="すべて"
                options={assignee_options(@assignees)}
              />
              <.input
                field={@filter_form[:sort]}
                type="select"
                label="並び順"
                options={sort_options()}
              />
            </div>
          </.form>
        </div>
      </div>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body p-0">
          <.table
            id="tickets"
            rows={@streams.tickets}
            row_item={fn {_id, ticket} -> ticket end}
          >
            <:col :let={ticket} label="ID">{ticket.public_id}</:col>
            <:col :let={ticket} label="Subject">{ticket.subject}</:col>
            <:col :let={ticket} label="Product">{ticket.product && ticket.product.name}</:col>
            <:col :let={ticket} label="Type">{ticket.type}</:col>
            <:col :let={ticket} label="Status">{ticket.status}</:col>
            <:col :let={ticket} label="Priority">{ticket.priority}</:col>
            <:col :let={ticket} label="Assignee">{assignee_label(ticket.assignee)}</:col>
            <:action :let={ticket}>
              <.link class="link" navigate={~p"/tickets/#{ticket.public_id}"}>
                詳細
              </.link>
            </:action>
          </.table>
        </div>
      </div>

      <div class="mt-4 flex flex-col gap-3 text-sm sm:flex-row sm:items-center sm:justify-between">
        <p class="opacity-70">{@total_count} 件</p>
        <div class="flex items-center gap-3">
          <.link
            :if={@page > 1}
            class="link"
            patch={page_path(@filters, @page - 1)}
          >
            前へ
          </.link>
          <span class="opacity-70">{@page} / {@total_pages}</span>
          <.link
            :if={@has_next?}
            class="link"
            patch={page_path(@filters, @page + 1)}
          >
            次へ
          </.link>
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
