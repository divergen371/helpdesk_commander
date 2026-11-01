defmodule HelpdeskCommander.Accounts.User.Changes.HashEmail do
  @moduledoc """
  Keeps `email_hash` in sync with the (encrypted) email argument.

  Encrypted email cannot be compared in SQL, so login and uniqueness checks
  use this digest instead.
  """

  use Ash.Resource.Change

  alias HelpdeskCommander.Support.PiiHash

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :email) do
      {:ok, email} when is_binary(email) ->
        Ash.Changeset.change_attribute(changeset, :email_hash, PiiHash.email(email))

      :error ->
        changeset

      _value ->
        changeset
    end
  end
end
