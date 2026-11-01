defmodule HelpdeskCommander.Helpdesk.Inquiry.Changes.CreateTicket do
  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    # Read encrypted arguments before AshCloak's before_action hook removes them.
    subject = Ash.Changeset.get_attribute(changeset, :subject)
    body = fetch_argument(changeset, :body)
    requester_id = Ash.Changeset.get_attribute(changeset, :requester_id)
    product_id = Ash.Changeset.get_attribute(changeset, :product_id)

    Ash.Changeset.before_action(changeset, fn changeset ->
      ticket_changeset =
        Ash.Changeset.for_create(Ticket, :create, %{
          subject: subject,
          description: body,
          requester_id: requester_id,
          product_id: product_id
        })

      case Ash.create(ticket_changeset, domain: Helpdesk) do
        {:ok, ticket} ->
          Ash.Changeset.force_change_attribute(changeset, :ticket_id, ticket.id)

        {:ok, ticket, _notifications} ->
          Ash.Changeset.force_change_attribute(changeset, :ticket_id, ticket.id)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp fetch_argument(changeset, field) do
    case Ash.Changeset.fetch_argument(changeset, field) do
      {:ok, value} -> value
      :error -> nil
    end
  end
end
