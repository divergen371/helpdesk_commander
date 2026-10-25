defmodule HelpdeskCommander.Helpdesk.Inquiry.Changes.ValidateTenant do
  @moduledoc false

  use Ash.Resource.Change

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    company_id = Ash.Changeset.get_attribute(changeset, :company_id)
    product_id = Ash.Changeset.get_attribute(changeset, :product_id)
    requester_id = Ash.Changeset.get_attribute(changeset, :requester_id)

    if is_nil(company_id) do
      changeset
    else
      validate_tenant(changeset, company_id, product_id, requester_id)
    end
  end

  defp validate_tenant(changeset, company_id, product_id, requester_id) do
    with {:ok, %Product{company_id: ^company_id}} <-
           Ash.get(Product, %{id: product_id}, domain: Helpdesk),
         {:ok, %User{company_id: ^company_id}} <-
           Ash.get(User, %{id: requester_id}, domain: Accounts) do
      changeset
    else
      _result ->
        Ash.Changeset.add_error(changeset,
          field: :product_id,
          message: "対象製品と依頼者の会社が一致しません"
        )
    end
  end
end
