defmodule HelpdeskCommander.Prototype.TicketStore do
  @moduledoc """
  In-memory store for LiveView prototyping.

  This module exists to validate UI feel and LiveView resource usage BEFORE
  Ash resources and database migrations are implemented.

  Notes:
  - Uses ETS for read concurrency.
  - All writes go through this GenServer.
  - Broadcasts updates via `HelpdeskCommander.PubSub`.

  Remove once real persistence is available.
  """

  use GenServer

  @meta_table :hcc_proto_ticket_meta
  @messages_table :hcc_proto_ticket_messages

  @max_seq 9_223_372_036_854_775_807

  @type ticket_id :: String.t()
  @type kind :: :internal_public | :internal_private

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_arg) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec topic(ticket_id()) :: String.t()
  def topic(ticket_id), do: "prototype_ticket:#{ticket_id}"

  @spec ensure_ticket(ticket_id()) :: :ok
  def ensure_ticket(ticket_id) do
    GenServer.call(__MODULE__, {:ensure_ticket, ticket_id})
  end

  @spec get_ticket(ticket_id()) :: map()
  def get_ticket(ticket_id) do
    ensure_ticket(ticket_id)

    case :ets.lookup(@meta_table, ticket_id) do
      [{^ticket_id, meta}] -> meta
      [] -> raise "ticket not found: #{inspect(ticket_id)}"
    end
  end

  @spec list_messages(ticket_id(), kind(), pos_integer()) :: [map()]
  def list_messages(ticket_id, kind, limit \\ 50) when limit > 0 do
    ensure_ticket(ticket_id)

    start_key = {ticket_id, kind, @max_seq}

    @messages_table
    |> take_prev(start_key, ticket_id, kind, limit, [])
    |> Enum.reverse()
    |> Enum.map(fn {_key, msg} -> msg end)
  end

  @spec append_message(ticket_id(), kind(), String.t(), String.t()) :: map()
  def append_message(ticket_id, kind, sender_name, body)
      when kind in [:internal_public, :internal_private] and is_binary(body) do
    GenServer.call(__MODULE__, {:append_message, ticket_id, kind, sender_name, body})
  end

  @spec seed_messages(ticket_id(), kind(), pos_integer()) :: :ok
  def seed_messages(ticket_id, kind, count) when count > 0 do
    GenServer.call(__MODULE__, {:seed_messages, ticket_id, kind, count})
  end

  @spec set_status(ticket_id(), String.t(), String.t()) :: map()
  def set_status(ticket_id, status, actor_name) when is_binary(status) do
    GenServer.call(__MODULE__, {:set_status, ticket_id, status, actor_name})
  end

  @impl GenServer
  def init(_state) do
    :ets.new(@meta_table, [
      :named_table,
      :set,
      :protected,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@messages_table, [
      :named_table,
      :ordered_set,
      :protected,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:ensure_ticket, ticket_id}, _from, state) do
    case :ets.lookup(@meta_table, ticket_id) do
      [{^ticket_id, _meta}] ->
        {:reply, :ok, state}

      [] ->
        now = DateTime.utc_now()

        meta = %{
          id: ticket_id,
          number: :erlang.phash2(ticket_id, 10_000_000),
          subject: "Prototype Ticket #{ticket_id}",
          status: "new",
          latest_message_at: nil,
          public_seq: 0,
          private_seq: 0,
          inserted_at: now,
          updated_at: now
        }

        :ets.insert(@meta_table, {ticket_id, meta})
        {:reply, :ok, state}
    end
  end

  def handle_call({:append_message, ticket_id, kind, sender_name, body}, _from, state) do
    meta = ensure_ticket_in_server(ticket_id)

    now = DateTime.utc_now()

    seq_key = seq_key(kind)
    next_seq = Map.fetch!(meta, seq_key) + 1

    msg = %{
      id: "#{Atom.to_string(kind)}-#{next_seq}",
      seq: next_seq,
      kind: kind,
      sender: sender_name,
      body: body,
      inserted_at: now
    }

    :ets.insert(@messages_table, {{ticket_id, kind, next_seq}, msg})

    updated_meta =
      meta
      |> Map.put(seq_key, next_seq)
      |> Map.put(:latest_message_at, now)
      |> Map.put(:updated_at, now)

    :ets.insert(@meta_table, {ticket_id, updated_meta})

    Phoenix.PubSub.broadcast(
      HelpdeskCommander.PubSub,
      topic(ticket_id),
      {:message, kind, msg, updated_meta}
    )

    {:reply, msg, state}
  end

  def handle_call({:seed_messages, ticket_id, kind, count}, _from, state) do
    meta = ensure_ticket_in_server(ticket_id)
    seq_key = seq_key(kind)

    {updated_meta, _last_msg} =
      Enum.reduce(1..count, {meta, nil}, fn i, {m, _last} ->
        now = DateTime.utc_now()
        next_seq = Map.fetch!(m, seq_key) + 1

        msg = %{
          id: "#{Atom.to_string(kind)}-#{next_seq}",
          seq: next_seq,
          kind: kind,
          sender: "seed",
          body: "seed message #{i}",
          inserted_at: now
        }

        :ets.insert(@messages_table, {{ticket_id, kind, next_seq}, msg})

        m =
          m
          |> Map.put(seq_key, next_seq)
          |> Map.put(:latest_message_at, now)
          |> Map.put(:updated_at, now)

        {m, msg}
      end)

    :ets.insert(@meta_table, {ticket_id, updated_meta})

    Phoenix.PubSub.broadcast(
      HelpdeskCommander.PubSub,
      topic(ticket_id),
      {:seeded, kind, count, updated_meta}
    )

    {:reply, :ok, state}
  end

  def handle_call({:set_status, ticket_id, status, actor_name}, _from, state) do
    meta = ensure_ticket_in_server(ticket_id)

    now = DateTime.utc_now()

    updated_meta =
      meta
      |> Map.put(:status, status)
      |> Map.put(:updated_at, now)

    :ets.insert(@meta_table, {ticket_id, updated_meta})

    Phoenix.PubSub.broadcast(
      HelpdeskCommander.PubSub,
      topic(ticket_id),
      {:status_changed, status, actor_name, updated_meta}
    )

    {:reply, updated_meta, state}
  end

  defp seq_key(:internal_public), do: :public_seq
  defp seq_key(:internal_private), do: :private_seq

  defp take_prev(_table, _key, _ticket_id, _kind, 0, acc), do: acc

  defp take_prev(table, key, ticket_id, kind, remaining, acc) do
    prev_key = :ets.prev(table, key)

    cond do
      prev_key == :"$end_of_table" ->
        acc

      match_ticket_kind?(prev_key, ticket_id, kind) ->
        case :ets.lookup(table, prev_key) do
          [{^prev_key, msg}] ->
            take_prev(table, prev_key, ticket_id, kind, remaining - 1, [{prev_key, msg} | acc])

          [] ->
            acc
        end

      true ->
        acc
    end
  end

  defp ensure_ticket_in_server(ticket_id) do
    case :ets.lookup(@meta_table, ticket_id) do
      [{^ticket_id, meta}] ->
        meta

      [] ->
        now = DateTime.utc_now()

        meta = %{
          id: ticket_id,
          number: :erlang.phash2(ticket_id, 10_000_000),
          subject: "Prototype Ticket #{ticket_id}",
          status: "new",
          latest_message_at: nil,
          public_seq: 0,
          private_seq: 0,
          inserted_at: now,
          updated_at: now
        }

        :ets.insert(@meta_table, {ticket_id, meta})
        meta
    end
  end

  defp match_ticket_kind?({ticket_id, kind, _seq}, ticket_id, kind), do: true
  defp match_ticket_kind?(_key, _ticket_id, _kind), do: false
end
