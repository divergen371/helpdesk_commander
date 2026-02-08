defmodule HelpdeskCommander.Helpdesk.Inquiry.Changes.CreateTicket do
  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset, _context ->
      subject = Ash.Changeset.get_attribute(changeset, :subject)
      body = Ash.Changeset.get_attribute(changeset, :body)
      requester_id = Ash.Changeset.get_attribute(changeset, :requester_id)

      ticket_changeset =
        Ash.Changeset.for_create(Ticket, :create, %{
          subject: subject,
          description: body,
          requester_id: requester_id
        })

      case Ash.create(ticket_changeset, domain: Helpdesk) do
        {:ok, ticket} ->
          Ash.Changeset.force_change_attribute(changeset, :ticket_id, ticket.id)

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
