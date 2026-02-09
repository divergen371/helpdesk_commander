defmodule HelpdeskCommander.Helpdesk.Changes.AssignCompanyFromRequester do
  use Ash.Resource.Change

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :company_id) do
      nil ->
        requester_id = Ash.Changeset.get_attribute(changeset, :requester_id)

        case requester_id && Ash.get(User, %{id: requester_id}, domain: Accounts) do
          {:ok, nil} ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "依頼者から会社情報を特定できません"
            )

          {:ok, user} ->
            Ash.Changeset.change_attribute(changeset, :company_id, user.company_id)

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :company_id,
              message: "依頼者から会社情報を特定できません"
            )
        end

      _company_id ->
        changeset
    end
  end
end
