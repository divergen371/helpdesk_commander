defmodule HelpdeskCommander.Accounts.Company.Changes.HashCompanyCode do
  use Ash.Resource.Change

  alias HelpdeskCommander.Support.CompanyCode

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :company_code) do
      nil ->
        changeset

      company_code ->
        case CompanyCode.hash(company_code) do
          {:ok, hashed} ->
            Ash.Changeset.change_attribute(changeset, :company_code_hash, hashed)

          {:error, :invalid_format} ->
            Ash.Changeset.add_error(changeset,
              field: :company_code,
              message: "会社IDは A-123456 形式で入力してください"
            )
        end
    end
  end
end
