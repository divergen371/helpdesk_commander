defmodule HelpdeskCommander.Workers.CreateTicketNotificationsWorker do
  @moduledoc """
  チケット関連イベントから、admin/leader 宛ての通知レコードを生成する。
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @notify_roles ~w(admin leader)

  @type notification_input :: %{
          required(:notification_type) => String.t(),
          required(:title) => String.t(),
          required(:body) => String.t(),
          required(:company_id) => integer(),
          required(:ticket_id) => integer(),
          optional(:actor_id) => integer() | nil,
          optional(:meta) => map()
        }

  @spec enqueue(notification_input()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(attrs) when is_map(attrs) do
    attrs
    |> stringify_keys()
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, notification_type} <- fetch_string(args, "notification_type"),
         {:ok, title} <- fetch_string(args, "title"),
         {:ok, body} <- fetch_string(args, "body"),
         {:ok, company_id} <- fetch_integer(args, "company_id"),
         {:ok, ticket_id} <- fetch_integer(args, "ticket_id") do
      actor_id = maybe_integer(args["actor_id"])
      meta = normalize_meta(args["meta"])

      case list_recipients(company_id, actor_id) do
        {:ok, []} ->
          :ok

        {:ok, recipients} ->
          create_notifications(
            recipients,
            notification_type,
            title,
            body,
            company_id,
            ticket_id,
            actor_id,
            meta
          )

        {:error, error} ->
          ErrorLog.log_error("workers.create_ticket_notifications.list_recipients", error,
            company_id: company_id,
            ticket_id: ticket_id
          )

          {:error, error}
      end
    else
      {:error, reason} ->
        ErrorLog.log_error("workers.create_ticket_notifications.invalid_args", reason, args: args)
        {:discard, reason}
    end
  end

  defp list_recipients(company_id, actor_id) do
    base_query = filter(User, company_id == ^company_id and status == "active" and role in ^@notify_roles)

    recipient_query =
      if is_integer(actor_id) do
        filter(base_query, id != ^actor_id)
      else
        base_query
      end

    Ash.read(recipient_query, domain: Accounts)
  end

  defp create_notifications(
         recipients,
         notification_type,
         title,
         body,
         company_id,
         ticket_id,
         actor_id,
         meta
       ) do
    failures =
      Enum.reduce(recipients, [], fn recipient, acc ->
        params = %{
          notification_type: notification_type,
          title: title,
          body: body,
          meta: meta,
          company_id: company_id,
          ticket_id: ticket_id,
          recipient_id: recipient.id,
          actor_id: actor_id
        }

        case TicketNotification
             |> Ash.Changeset.for_create(:create, params)
             |> Ash.create(domain: Helpdesk) do
          {:ok, _notification} ->
            acc

          {:error, error} ->
            ErrorLog.log_error("workers.create_ticket_notifications.create", error,
              recipient_id: recipient.id,
              ticket_id: ticket_id
            )

            [recipient.id | acc]
        end
      end)

    if failures == [] do
      :ok
    else
      {:error, {:create_failed, Enum.reverse(failures)}}
    end
  end

  defp fetch_string(map, key) do
    value = Map.get(map, key)

    if is_binary(value) and value != "" do
      {:ok, value}
    else
      {:error, {:invalid_string, key}}
    end
  end

  defp fetch_integer(map, key) do
    case maybe_integer(Map.get(map, key)) do
      value when is_integer(value) -> {:ok, value}
      _value -> {:error, {:invalid_integer, key}}
    end
  end

  defp maybe_integer(value) when is_integer(value), do: value

  defp maybe_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp maybe_integer(_value), do: nil

  defp normalize_meta(value) when is_map(value), do: value
  defp normalize_meta(_value), do: %{}

  defp stringify_keys(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end
end
