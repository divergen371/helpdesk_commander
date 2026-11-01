defmodule HelpdeskCommander.Notifications.External.Chat do
  @moduledoc """
  Delivers a ticket notification to a chat webhook (Slack-compatible).
  """

  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec deliver(HelpdeskCommander.Helpdesk.TicketNotification.t()) ::
          :ok | :skipped | {:error, term()}
  def deliver(%{chat_sent_at: %DateTime{}}), do: :skipped

  def deliver(%{} = notification) do
    if External.chat_enabled?() do
      post(notification)
    else
      :skipped
    end
  end

  defp post(notification) do
    options = Keyword.merge([json: %{text: text(notification)}, retry: false], External.chat_req_options())

    case Req.post(External.chat_webhook_url(), options) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} ->
        ErrorLog.log_error("notifications.external.chat.status", {:http_status, status},
          notification_id: notification.id
        )

        {:error, {:http_status, status}}

      {:error, error} ->
        ErrorLog.log_error("notifications.external.chat.deliver", error, notification_id: notification.id)

        {:error, error}
    end
  end

  defp text(notification) do
    "#{notification.title}\n#{notification.body}"
  end
end
