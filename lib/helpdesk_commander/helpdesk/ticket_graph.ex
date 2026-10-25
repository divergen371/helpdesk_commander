defmodule HelpdeskCommander.Helpdesk.TicketGraph do
  @moduledoc false

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketLink
  alias HelpdeskCommander.Helpdesk.TicketRelations

  @max_links 30
  @max_overview_tickets 150
  @max_overview_links 400

  @relation_style %{
    "reopened_from" => {"#dc2626", 0.95},
    "duplicate_of" => {"#7c3aed", 0.8},
    "blocks" => {"#2563eb", 0.7},
    "blocked_by" => {"#2563eb", 0.7},
    "related" => {"#64748b", 0.4}
  }

  @spec build(Ticket.t()) ::
          {:ok, %{nodes: [map()], edges: [map()]}} | {:error, term()}
  def build(%Ticket{} = ticket) do
    with {:ok, links} <- TicketRelations.list_links(ticket) do
      links = Enum.take(links, @max_links)

      indexed_links = Enum.with_index(links)
      nodes = Enum.uniq_by([root_node(ticket) | Enum.map(indexed_links, &related_node/1)], & &1["id"])

      edges =
        Enum.map(indexed_links, fn {link, index} -> edge(ticket, link, index) end)

      {:ok, %{nodes: nodes, edges: edges}}
    end
  end

  @spec build_overview(integer()) ::
          {:ok, %{nodes: [map()], edges: [map()]}} | {:error, term()}
  def build_overview(company_id) do
    tickets_query =
      Ticket
      |> filter(company_id == ^company_id)
      |> sort(inserted_at: :desc)
      |> Ash.Query.limit(@max_overview_tickets)

    links_query =
      TicketLink
      |> filter(company_id == ^company_id)
      |> Ash.Query.limit(@max_overview_links)

    with {:ok, tickets} <- Ash.read(tickets_query, domain: Helpdesk),
         {:ok, links} <- Ash.read(links_query, domain: Helpdesk) do
      indexed_tickets = Enum.with_index(tickets)
      nodes = Enum.map(indexed_tickets, &overview_node/1)
      by_id = Map.new(tickets, &{&1.id, &1})

      edges =
        links
        |> Enum.with_index()
        |> Enum.flat_map(fn {link, index} -> overview_edge(link, index, by_id) end)

      {:ok, %{nodes: nodes, edges: edges}}
    end
  end

  defp root_node(%Ticket{} = ticket) do
    %{
      "id" => ticket.public_id,
      "label" => ticket.subject,
      "x" => 0.0,
      "y" => 0.0,
      "size" => 22,
      "color" => "#0f172a",
      "root" => true,
      "status" => ticket.status,
      "priority" => ticket.priority,
      "url" => "/tickets/#{ticket.public_id}"
    }
  end

  defp related_node({entry, index}) do
    angle = index * 2 * :math.pi() / 6
    radius = 3.0 + rem(index, 3)

    %{
      "id" => entry.ticket.public_id,
      "label" => entry.ticket.subject,
      "x" => radius * :math.cos(angle),
      "y" => radius * :math.sin(angle),
      "size" => priority_size(entry.ticket.priority),
      "color" => status_color(entry.ticket.status),
      "status" => entry.ticket.status,
      "priority" => entry.ticket.priority,
      "url" => "/tickets/#{entry.ticket.public_id}"
    }
  end

  defp edge(ticket, %{link: link, direction: direction, ticket: other}, index) do
    {color, score} = Map.get(@relation_style, link.relation_type, {"#64748b", 0.4})

    {source, target} =
      case direction do
        :outgoing -> {ticket.public_id, other.public_id}
        :incoming -> {other.public_id, ticket.public_id}
      end

    %{
      "id" => "edge-#{index}",
      "source" => source,
      "target" => target,
      "label" => "#{link.relation_type} #{score}",
      "relation" => link.relation_type,
      "score" => score,
      "color" => color
    }
  end

  defp overview_node({ticket, index}) do
    columns = 10
    spacing = 5.0

    %{
      "id" => ticket.public_id,
      "label" => ticket.subject,
      "x" => rem(index, columns) * spacing,
      "y" => div(index, columns) * spacing,
      "size" => priority_size(ticket.priority),
      "color" => status_color(ticket.status),
      "status" => ticket.status,
      "priority" => ticket.priority,
      "url" => "/tickets/#{ticket.public_id}"
    }
  end

  defp overview_edge(link, index, by_id) do
    with %Ticket{} = ticket <- Map.get(by_id, link.ticket_id),
         %Ticket{} = related <- Map.get(by_id, link.related_ticket_id) do
      {color, score} = Map.get(@relation_style, link.relation_type, {"#64748b", 0.4})

      [
        %{
          "id" => "edge-#{index}",
          "source" => ticket.public_id,
          "target" => related.public_id,
          "label" => "#{link.relation_type} #{score}",
          "relation" => link.relation_type,
          "score" => score,
          "color" => color
        }
      ]
    else
      _entry -> []
    end
  end

  defp priority_size("p1"), do: 18
  defp priority_size("p2"), do: 16
  defp priority_size("p3"), do: 14
  defp priority_size(_priority), do: 12

  defp status_color("verified"), do: "#059669"
  defp status_color("closed"), do: "#475569"
  defp status_color("resolved"), do: "#0891b2"
  defp status_color("waiting"), do: "#d97706"
  defp status_color(_status), do: "#64748b"
end
