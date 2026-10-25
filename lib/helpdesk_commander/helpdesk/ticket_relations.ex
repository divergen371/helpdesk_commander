defmodule HelpdeskCommander.Helpdesk.TicketRelations do
  @moduledoc false

  import Ash.Query

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketLink

  @spec list_links(Ticket.t()) ::
          {:ok, [%{link: TicketLink.t(), direction: :incoming | :outgoing, ticket: Ticket.t()}]}
          | {:error, term()}
  def list_links(%Ticket{id: ticket_id}) do
    query = filter(TicketLink, ticket_id == ^ticket_id or related_ticket_id == ^ticket_id)

    with {:ok, links} <- Ash.read(query, domain: Helpdesk),
         {:ok, links} <- Ash.load(links, [:ticket, :related_ticket], domain: Helpdesk) do
      links =
        links
        |> Enum.map(fn link ->
          if link.ticket_id == ticket_id do
            %{link: link, direction: :outgoing, ticket: link.related_ticket}
          else
            %{link: link, direction: :incoming, ticket: link.ticket}
          end
        end)
        |> Enum.sort_by(& &1.link.inserted_at, {:desc, DateTime})

      {:ok, links}
    end
  end

  @spec linkable_tickets(Ticket.t()) :: {:ok, [Ticket.t()]} | {:error, term()}
  def linkable_tickets(%Ticket{id: ticket_id, company_id: company_id}) do
    query =
      Ticket
      |> filter(company_id == ^company_id and id != ^ticket_id)
      |> sort(inserted_at: :desc)
      |> Ash.Query.limit(100)

    Ash.read(query, domain: Helpdesk)
  end

  @spec create_link(Ticket.t(), term(), String.t(), term()) ::
          {:ok, TicketLink.t()} | {:error, term()}
  def create_link(%Ticket{} = ticket, related_ticket_id, relation_type, current_user) do
    with {related_ticket_id, _rest} <-
           related_ticket_id |> to_string() |> Integer.parse(),
         {:ok, %Ticket{} = related_ticket} <-
           Ash.get(Ticket, %{id: related_ticket_id}, domain: Helpdesk) do
      cond do
        related_ticket.id == ticket.id ->
          {:error, :invalid_relation}

        related_ticket.company_id != ticket.company_id ->
          {:error, :different_company}

        true ->
          TicketLink
          |> Ash.Changeset.for_create(:create, %{
            ticket_id: ticket.id,
            related_ticket_id: related_ticket_id,
            relation_type: relation_type,
            created_by_id: current_user.id
          })
          |> Ash.create(domain: Helpdesk)
      end
    else
      :error -> {:error, :invalid_ticket}
      {:error, error} -> {:error, error}
    end
  end

  @spec delete_link(Ticket.t(), term()) :: :ok | {:error, term()}
  def delete_link(%Ticket{id: ticket_id}, link_id) do
    with {link_id, _rest} <- link_id |> to_string() |> Integer.parse(),
         {:ok, %TicketLink{} = link} <-
           TicketLink
           |> filter(
             id == ^link_id and
               (ticket_id == ^ticket_id or related_ticket_id == ^ticket_id)
           )
           |> Ash.read_one(domain: Helpdesk) do
      Ash.destroy(link, domain: Helpdesk)
    else
      :error -> {:error, :invalid_link}
      {:ok, nil} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end
end
