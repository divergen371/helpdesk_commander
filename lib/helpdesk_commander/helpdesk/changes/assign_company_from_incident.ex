defmodule HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromIncident do
  use Ash.Resource.Change

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Incident

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :company_id) do
      nil ->
        incident_id = Ash.Changeset.get_attribute(changeset, :incident_id)

        case incident_id && Ash.get(Incident, incident_id, domain: Helpdesk, authorize?: false) do
          {:ok, %Incident{company_id: company_id}} ->
            Ash.Changeset.change_attribute(changeset, :company_id, company_id)

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "インシデントから会社情報を特定できません"
            )
        end

      _company_id ->
        changeset
    end
  end
end
