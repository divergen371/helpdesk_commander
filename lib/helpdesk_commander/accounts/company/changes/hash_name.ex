defmodule HelpdeskCommander.Accounts.Company.Changes.HashName do
  @moduledoc """
  Keeps `name_hash` in sync with the (encrypted) company name argument.
  """

  use Ash.Resource.Change

  alias HelpdeskCommander.Support.PiiHash

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :name) do
      {:ok, name} when is_binary(name) ->
        Ash.Changeset.change_attribute(changeset, :name_hash, PiiHash.company_name(name))

      :error ->
        changeset

      _value ->
        changeset
    end
  end
end
