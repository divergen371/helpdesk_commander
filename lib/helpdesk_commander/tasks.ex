defmodule HelpdeskCommander.Tasks do
  @moduledoc false

  use Ash.Domain

  import Ash.Query

  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommander.Tasks.TaskEvent
  alias HelpdeskCommander.Tasks.TicketTaskLink

  resources do
    resource HelpdeskCommander.Tasks.Task
    resource HelpdeskCommander.Tasks.TaskEvent
    resource HelpdeskCommander.Tasks.TicketTaskLink
  end

  @spec get_task(String.t(), integer(), keyword()) :: {:ok, Task.t() | nil} | {:error, term()}
  def get_task(public_id, company_id, opts \\ []) do
    Task
    |> filter(public_id == ^public_id and company_id == ^company_id)
    |> Ash.read_one(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec list_tasks(integer(), keyword()) :: {:ok, [Task.t()]} | {:error, term()}
  def list_tasks(company_id, opts \\ []) do
    Task
    |> filter(company_id == ^company_id)
    |> sort(inserted_at: :desc)
    |> Ash.read(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec count_tasks(integer(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count_tasks(company_id, opts \\ []) do
    Task
    |> filter(company_id == ^company_id)
    |> Ash.count(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec list_recent_tasks(integer(), pos_integer(), keyword()) ::
          {:ok, [Task.t()]} | {:error, term()}
  def list_recent_tasks(company_id, limit \\ 5, opts \\ []) do
    Task
    |> filter(company_id == ^company_id)
    |> sort(inserted_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec list_priority_events(integer(), keyword()) :: {:ok, [TaskEvent.t()]} | {:error, term()}
  def list_priority_events(task_id, opts \\ []) do
    with {:ok, events} <-
           TaskEvent
           |> filter(task_id == ^task_id and event_type == "priority_changed")
           |> sort(id: :desc)
           |> Ash.read(Keyword.put(opts, :domain, __MODULE__)) do
      Ash.load(events, [:actor], Keyword.put(opts, :domain, __MODULE__))
    end
  end

  @spec destroy_task(Task.t(), keyword()) :: :ok | {:ok, Task.t()} | {:error, term()}
  def destroy_task(task, opts \\ []), do: Ash.destroy(task, Keyword.put(opts, :domain, __MODULE__))

  @spec list_ticket_task_links(integer(), keyword()) ::
          {:ok, [TicketTaskLink.t()]} | {:error, term()}
  def list_ticket_task_links(ticket_id, opts \\ []) do
    with {:ok, links} <-
           TicketTaskLink
           |> filter(ticket_id == ^ticket_id)
           |> Ash.read(Keyword.put(opts, :domain, __MODULE__)) do
      Ash.load(links, [:task], Keyword.put(opts, :domain, __MODULE__))
    end
  end

  @spec list_linkable_tasks(integer(), [integer()], keyword()) :: {:ok, [Task.t()]} | {:error, term()}
  def list_linkable_tasks(company_id, linked_ids, opts \\ []) do
    linked = MapSet.new(linked_ids)

    query =
      Task
      |> filter(company_id == ^company_id)
      |> sort(title: :asc)

    case Ash.read(query, Keyword.put(opts, :domain, __MODULE__)) do
      {:ok, tasks} -> {:ok, Enum.reject(tasks, &MapSet.member?(linked, &1.id))}
      error -> error
    end
  end

  @spec create_ticket_task_link(map(), keyword()) ::
          {:ok, TicketTaskLink.t()} | {:error, term()}
  def create_ticket_task_link(params, opts \\ []),
    do: TicketTaskLink.create_ticket_task_link(params, opts)

  @spec get_ticket_task_link(integer(), integer(), keyword()) ::
          {:ok, TicketTaskLink.t() | nil} | {:error, term()}
  def get_ticket_task_link(id, ticket_id, opts \\ []) do
    TicketTaskLink
    |> filter(id == ^id and ticket_id == ^ticket_id)
    |> Ash.read_one(Keyword.put(opts, :domain, __MODULE__))
  end

  @spec destroy_ticket_task_link(TicketTaskLink.t(), keyword()) :: :ok | {:ok, TicketTaskLink.t()} | {:error, term()}
  def destroy_ticket_task_link(link, opts \\ []), do: Ash.destroy(link, Keyword.put(opts, :domain, __MODULE__))
end
