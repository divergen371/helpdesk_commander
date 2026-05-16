defmodule HelpdeskCommander.Helpdesk.Ticket.Checks.StatusDoesNotRequirePrivilegedRole do
  use Ash.Policy.SimpleCheck

  @privileged_statuses ~w(verified closed)

  @impl Ash.Policy.Check
  def describe(_opts), do: "target status does not require admin or leader"
  @impl Ash.Policy.SimpleCheck
  def match?(_actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    status = Ash.Changeset.get_argument(changeset, :status)
    {:ok, status not in @privileged_statuses}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}
end
