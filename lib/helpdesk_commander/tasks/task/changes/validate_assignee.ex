defmodule HelpdeskCommander.Tasks.Task.Changes.ValidateAssignee do
  @moduledoc false

  use Ash.Resource.Change

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    company_id =
      Ash.Changeset.get_attribute(changeset, :company_id) ||
        Map.get(changeset.data, :company_id)

    case Ash.Changeset.get_attribute(changeset, :assignee_id) do
      nil ->
        changeset

      assignee_id ->
        case Ash.get(User, %{id: assignee_id}, domain: Accounts) do
          {:ok, %User{} = assignee} ->
            if Authorization.same_company?(assignee, company_id) do
              changeset
            else
              Ash.Changeset.add_error(changeset,
                field: :assignee_id,
                message: "別会社のユーザーは担当者にできません"
              )
            end

          _result ->
            Ash.Changeset.add_error(changeset,
              field: :assignee_id,
              message: "担当者が見つかりません"
            )
        end
    end
  end
end
