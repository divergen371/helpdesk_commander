defmodule HelpdeskCommander.Workers.DeliverTicketNotificationWorker do
  @moduledoc """
  Delivers an existing in-app notification to the configured external channels.

  Delivery is idempotent: each channel records its sent timestamp on the
  notification, so retries do not send duplicates.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Notifications.External.Chat
  alias HelpdeskCommander.Notifications.External.Email
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec enqueue(integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(notification_id) do
    %{notification_id: notification_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => notification_id}}) do
    case Ash.get(TicketNotification, notification_id, domain: Helpdesk, authorize?: false) do
      {:ok, nil} ->
        :ok

      {:ok, %TicketNotification{} = notification} ->
        deliver(notification)

      {:error, error} ->
        ErrorLog.log_error("workers.deliver_notification.load", error, notification_id: notification_id)

        {:error, error}
    end
  end

  defp deliver(notification) do
    with :ok <- deliver_email(notification) do
      deliver_chat(notification)
    end
  end

  defp deliver_email(notification) do
    case Email.deliver(notification) do
      :skipped -> :ok
      :ok -> mark(notification, :mark_email_sent)
      {:error, error} -> {:error, error}
    end
  end

  defp deliver_chat(notification) do
    case Chat.deliver(notification) do
      :skipped -> :ok
      :ok -> mark(notification, :mark_chat_sent)
      {:error, error} -> {:error, error}
    end
  end

  defp mark(notification, action) do
    case notification
         |> Ash.Changeset.for_update(action, %{})
         |> Ash.update(domain: Helpdesk, authorize?: false) do
      {:ok, _notification} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
