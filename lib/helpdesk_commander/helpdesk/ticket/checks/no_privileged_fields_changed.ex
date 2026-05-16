defmodule HelpdeskCommander.Helpdesk.Ticket.Checks.NoPrivilegedFieldsChanged do
  use Ash.Policy.SimpleCheck

  @privileged_fields [:priority, :assignee_id]

  @impl Ash.Policy.Check
  def describe(_opts), do: "priority and assignee are unchanged"
  @impl Ash.Policy.SimpleCheck
  def match?(_actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    {:ok, not Enum.any?(@privileged_fields, &attribute_changed?(changeset, &1))}
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  defp attribute_changed?(changeset, field) do
    Ash.Changeset.get_attribute(changeset, field) != Map.get(changeset.data, field)
  end
end
