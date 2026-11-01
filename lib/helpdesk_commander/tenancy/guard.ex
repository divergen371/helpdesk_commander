defmodule HelpdeskCommander.Tenancy.Guard do
  @moduledoc """
  Rejects writes that target a company other than the actor's company.

  Runs as a resource-level change on create, update, and destroy so it also
  covers actions added later.
  """

  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &ensure_company/1)
  end

  defp ensure_company(changeset) do
    actor = get_in(changeset.context, [:private, :actor])

    company_id =
      Ash.Changeset.get_attribute(changeset, :company_id) ||
        Map.get(changeset.data, :company_id)

    cond do
      is_nil(actor) -> changeset
      is_nil(company_id) -> changeset
      Map.get(actor, :company_id) == company_id -> changeset
      true -> Ash.Changeset.add_error(changeset, field: :company_id, message: "他の会社のデータは変更できません")
    end
  end
end
