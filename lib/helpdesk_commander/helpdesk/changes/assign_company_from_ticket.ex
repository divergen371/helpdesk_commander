defmodule HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromTicket do
  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk.Ticket

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :company_id) do
      nil ->
        ticket_id = Ash.Changeset.get_attribute(changeset, :ticket_id)

        case ticket_id && Ash.get(Ticket, %{id: ticket_id}, domain: HelpdeskCommander.Helpdesk) do
          {:ok, nil} ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "チケットから会社情報を特定できません"
            )

          {:ok, ticket} ->
            Ash.Changeset.change_attribute(changeset, :company_id, ticket.company_id)

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "チケットから会社情報を特定できません"
            )
        end

      _company_id ->
        changeset
    end
  end
end
