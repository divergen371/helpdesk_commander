defmodule HelpdeskCommander.Helpdesk do
  @moduledoc false

  use Ash.Domain

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketEvent
  alias HelpdeskCommander.Helpdesk.TicketVerification

  @statuses ~w(new triage in_progress waiting resolved verified closed)
  @priorities ~w(p1 p2 p3 p4)
  @types ~w(question incident request)

  resources do
    resource HelpdeskCommander.Helpdesk.Conversation
    resource HelpdeskCommander.Helpdesk.ConversationMessage
    resource HelpdeskCommander.Helpdesk.Inquiry
    resource HelpdeskCommander.Helpdesk.Product
    resource HelpdeskCommander.Helpdesk.Ticket
    resource HelpdeskCommander.Helpdesk.TicketEvent
    resource HelpdeskCommander.Helpdesk.TicketNotification
    resource HelpdeskCommander.Helpdesk.TicketVerification
    resource HelpdeskCommander.Helpdesk.TicketLink
  end

  ## Tickets

  @spec get_ticket(integer()) :: {:ok, Ticket.t() | nil} | {:error, term()}
  def get_ticket(id), do: Ticket.get_ticket(id)

  @spec get_ticket_by_public_id(String.t()) :: {:ok, Ticket.t() | nil} | {:error, term()}
  def get_ticket_by_public_id(public_id), do: Ticket.get_ticket_by_public_id(public_id)

  @spec create_ticket(map(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def create_ticket(params, opts \\ []), do: Ticket.create_ticket(params, opts)

  @spec update_ticket(Ticket.t(), map(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def update_ticket(ticket, params, opts \\ []) do
    ticket
    |> Ash.Changeset.for_update(:update, params)
    |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec set_ticket_status(Ticket.t(), map(), keyword()) :: {:ok, Ticket.t()} | {:error, term()}
  def set_ticket_status(ticket, params, opts \\ []) do
    ticket
    |> Ash.Changeset.for_update(:set_status, params)
    |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec load_ticket_product(Ticket.t()) :: {:ok, Ticket.t()} | {:error, term()}
  def load_ticket_product(%Ticket{} = ticket) do
    Ash.load(ticket, [:product], domain: __MODULE__)
  end

  @spec load_ticket_stats(Ticket.t()) :: {:ok, Ticket.t()} | {:error, term()}
  def load_ticket_stats(%Ticket{} = ticket) do
    Ash.load(ticket, [:verification_count, :latest_event_at], domain: __MODULE__)
  end

  @spec count_tickets(integer(), User.t() | nil, boolean()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count_tickets(company_id, user, external?) do
    company_id
    |> ticket_scope(user, external?)
    |> Ash.count(domain: __MODULE__)
  end

  @spec list_recent_tickets(integer(), User.t() | nil, boolean(), pos_integer()) ::
          {:ok, [Ticket.t()]} | {:error, term()}
  def list_recent_tickets(company_id, user, external?, limit \\ 5) do
    with {:ok, tickets} <-
           company_id
           |> ticket_scope(user, external?)
           |> sort(inserted_at: :desc)
           |> Ash.Query.limit(limit)
           |> Ash.read(domain: __MODULE__) do
      Ash.load(tickets, [:product], domain: __MODULE__)
    end
  end

  @spec list_tickets(integer(), User.t() | nil, boolean(), map(), pos_integer(), pos_integer()) ::
          {:ok, %{tickets: [Ticket.t()], total_count: integer(), has_next?: boolean()}}
          | {:error, term()}
  def list_tickets(company_id, user, external?, filters, page, page_size) do
    query =
      company_id
      |> ticket_scope(user, external?)
      |> apply_ticket_filters(filters)
      |> sort_tickets(filters[:sort])

    offset = (page - 1) * page_size

    with {:ok, %Ash.Page.Offset{results: tickets, count: total_count, more?: has_next?}} <-
           Ash.read(query, domain: __MODULE__, page: [limit: page_size, offset: offset, count: true]),
         {:ok, tickets} <- Ash.load(tickets, [:product, :assignee], domain: __MODULE__) do
      {:ok, %{tickets: tickets, total_count: total_count, has_next?: has_next?}}
    end
  end

  defp ticket_scope(company_id, user, external?) do
    query = filter(Ticket, company_id == ^company_id or visibility_scope == "global")

    if external? and match?(%User{}, user) do
      filter(query, requester_id == ^user.id)
    else
      query
    end
  end

  defp apply_ticket_filters(query, filters) do
    query
    |> filter_ticket_query(filters[:q])
    |> filter_ticket_status(filters[:status])
    |> filter_ticket_priority(filters[:priority])
    |> filter_ticket_type(filters[:type])
    |> filter_ticket_assignee(filters[:assignee_id])
  end

  defp filter_ticket_query(query, value) when is_binary(value) and value != "" do
    pattern = "%#{escape_like(value)}%"

    filter(query, ilike(subject, ^pattern) or public_id == ^value)
  end

  defp filter_ticket_query(query, _value), do: query

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp filter_ticket_status(query, value) when value in @statuses,
    do: filter(query, status == ^value)

  defp filter_ticket_status(query, _value), do: query

  defp filter_ticket_priority(query, value) when value in @priorities,
    do: filter(query, priority == ^value)

  defp filter_ticket_priority(query, _value), do: query

  defp filter_ticket_type(query, value) when value in @types,
    do: filter(query, type == ^value)

  defp filter_ticket_type(query, _value), do: query

  defp filter_ticket_assignee(query, "unassigned"), do: filter(query, is_nil(assignee_id))

  defp filter_ticket_assignee(query, value) when is_binary(value) do
    case Integer.parse(value) do
      {assignee_id, _rest} -> filter(query, assignee_id == ^assignee_id)
      :error -> query
    end
  end

  defp filter_ticket_assignee(query, _value), do: query

  defp sort_tickets(query, "oldest"), do: sort(query, inserted_at: :asc)
  defp sort_tickets(query, "priority"), do: sort(query, priority: :asc, inserted_at: :desc)
  defp sort_tickets(query, "status"), do: sort(query, status: :asc, inserted_at: :desc)
  defp sort_tickets(query, _sort), do: sort(query, inserted_at: :desc)

  ## Products

  @spec get_product(integer()) :: {:ok, Product.t() | nil} | {:error, term()}
  def get_product(id), do: Product.get_product(id)

  @spec get_company_product(integer(), integer() | String.t()) ::
          {:ok, Product.t() | nil} | {:error, term()}
  def get_company_product(company_id, id) do
    Product
    |> filter(id == ^id and company_id == ^company_id)
    |> Ash.read_one(domain: __MODULE__)
  end

  @spec list_products(integer(), keyword()) :: {:ok, [Product.t()]} | {:error, term()}
  def list_products(company_id, opts \\ []) do
    Product
    |> filter(company_id == ^company_id)
    |> filter_active_products(Keyword.get(opts, :active_only, false))
    |> filter_product_query(Keyword.get(opts, :query))
    |> sort(name: :asc)
    |> Ash.read(domain: __MODULE__)
  end

  defp filter_product_query(query, value) when is_binary(value) and value != "" do
    filter(query, ilike(name, ^"%#{escape_like(value)}%"))
  end

  defp filter_product_query(query, _value), do: query

  defp filter_active_products(query, true), do: filter(query, active == true)
  defp filter_active_products(query, _active_only?), do: query

  @spec update_product(Product.t(), map(), keyword()) :: {:ok, Product.t()} | {:error, term()}
  def update_product(product, params, opts \\ []) do
    product
    |> Ash.Changeset.for_update(:update, params)
    |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec count_active_products(integer()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_active_products(company_id) do
    Product
    |> filter(company_id == ^company_id and active == true)
    |> Ash.count(domain: __MODULE__)
  end

  ## Conversations and messages

  @spec get_conversation(integer(), String.t()) ::
          {:ok, Conversation.t() | nil} | {:error, term()}
  def get_conversation(ticket_id, kind) do
    Conversation
    |> filter(ticket_id == ^ticket_id and kind == ^kind)
    |> Ash.read_one(domain: __MODULE__)
  end

  @spec create_conversation(map(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def create_conversation(params, opts \\ []), do: Conversation.create_conversation(params, opts)

  @spec ensure_conversation(Ticket.t(), String.t()) ::
          {:ok, Conversation.t()} | {:error, term()}
  def ensure_conversation(%Ticket{} = ticket, kind) do
    case get_conversation(ticket.id, kind) do
      {:ok, %Conversation{} = conversation} ->
        {:ok, conversation}

      {:ok, nil} ->
        create_conversation(%{
          ticket_id: ticket.id,
          kind: kind,
          created_by_id: ticket.requester_id
        })

      {:error, error} ->
        {:error, error}
    end
  end

  @spec list_messages(integer(), integer() | nil, pos_integer(), keyword()) ::
          {:ok, {[ConversationMessage.t()], boolean(), integer() | nil}} | {:error, term()}
  def list_messages(conversation_id, before_id \\ nil, limit \\ 20, opts \\ []) do
    ConversationMessage
    |> filter(conversation_id == ^conversation_id and is_nil(deleted_at))
    |> paginate(before_id, limit, opts)
  end

  @spec get_message_in_conversations(integer(), [integer()], keyword()) ::
          {:ok, ConversationMessage.t() | nil} | {:error, term()}
  def get_message_in_conversations(id, conversation_ids, opts \\ []) do
    ConversationMessage
    |> filter(id == ^id and conversation_id in ^conversation_ids and is_nil(deleted_at))
    |> Ash.read_one(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec create_message(map(), keyword()) :: {:ok, ConversationMessage.t()} | {:error, term()}
  def create_message(params, opts \\ []), do: ConversationMessage.create_message(params, opts)

  @spec edit_message(ConversationMessage.t(), map(), keyword()) ::
          {:ok, ConversationMessage.t()} | {:error, term()}
  def edit_message(message, params, opts \\ []) do
    message
    |> Ash.Changeset.for_update(:edit, params)
    |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec soft_delete_message(ConversationMessage.t(), keyword()) ::
          {:ok, ConversationMessage.t()} | {:error, term()}
  def soft_delete_message(message, opts \\ []) do
    message
    |> Ash.Changeset.for_update(:soft_delete, %{})
    |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
  end

  ## Events and verifications

  @spec list_events(integer(), integer() | nil, pos_integer()) ::
          {:ok, {[TicketEvent.t()], boolean(), integer() | nil}} | {:error, term()}
  def list_events(ticket_id, before_id \\ nil, limit \\ 20) do
    TicketEvent
    |> filter(ticket_id == ^ticket_id)
    |> paginate(before_id, limit, [])
  end

  @spec create_ticket_event(map(), keyword()) :: {:ok, TicketEvent.t()} | {:error, term()}
  def create_ticket_event(params, opts \\ []), do: TicketEvent.create_ticket_event(params, opts)

  @spec list_verifications(integer(), pos_integer()) ::
          {:ok, [TicketVerification.t()]} | {:error, term()}
  def list_verifications(ticket_id, limit \\ 20) do
    TicketVerification
    |> filter(ticket_id == ^ticket_id)
    |> sort(id: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read(domain: __MODULE__)
  end

  @spec create_inquiry(map(), keyword()) :: {:ok, Inquiry.t()} | {:error, term()}
  def create_inquiry(params, opts \\ []), do: Inquiry.create_inquiry(params, opts)

  defp paginate(query, before_id, limit, opts) do
    query =
      query
      |> sort(id: :desc)
      |> maybe_before_id(before_id)
      |> Ash.Query.limit(limit + 1)

    case Ash.read(query, Keyword.put(opts, :domain, __MODULE__)) do
      {:ok, rows} ->
        {rows, has_more?} =
          if length(rows) > limit do
            {Enum.take(rows, limit), true}
          else
            {rows, false}
          end

        ordered = Enum.reverse(rows)
        {:ok, {ordered, has_more?, oldest_id(ordered)}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_before_id(query, nil), do: query
  defp maybe_before_id(query, before_id), do: filter(query, id < ^before_id)

  defp oldest_id([]), do: nil
  defp oldest_id([first | _rest]), do: first.id
end
