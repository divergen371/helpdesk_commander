defmodule HelpdeskCommander.Notifications.External.Email do
  @moduledoc """
  Delivers a ticket notification to the recipient by email.
  """

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @spec deliver(TicketNotification.t()) :: :ok | :skipped | {:error, term()}
  def deliver(%TicketNotification{email_sent_at: %DateTime{}}), do: :skipped

  def deliver(%TicketNotification{} = notification) do
    if External.email_enabled?() do
      with {:ok, recipient} <- Accounts.get_user(notification.recipient_id),
           :ok <- ensure_recipient(recipient, notification) do
        deliver_email(notification, recipient)
      end
    else
      :skipped
    end
  end

  defp ensure_recipient(%{email: email}, _notification) when is_binary(email) and email != "",
    do: :ok

  defp ensure_recipient(_recipient, _notification), do: :skipped

  defp deliver_email(notification, recipient) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to({recipient.display_name, recipient.email})
      |> Swoosh.Email.from({"Helpdesk Commander", External.from_email()})
      |> Swoosh.Email.subject(notification.title)
      |> Swoosh.Email.text_body(body(notification))

    case HelpdeskCommander.Mailer.deliver(email) do
      {:ok, _email} ->
        :ok

      {:error, error} ->
        ErrorLog.log_error("notifications.external.email.deliver", error,
          notification_id: notification.id,
          recipient_id: recipient.id
        )

        {:error, error}
    end
  end

  defp body(notification) do
    url = HelpdeskCommanderWeb.Endpoint.url() <> "/tickets/#{ticket_public_id(notification)}"

    [notification.body, "", "チケット: #{url}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp ticket_public_id(%TicketNotification{ticket_id: ticket_id}) do
    case Ash.get(Ticket, ticket_id, domain: Helpdesk, authorize?: false) do
      {:ok, %Ticket{public_id: public_id}} -> public_id
      _result -> ticket_id
    end
  end
end
