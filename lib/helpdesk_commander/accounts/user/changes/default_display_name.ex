defmodule HelpdeskCommander.Accounts.User.Changes.DefaultDisplayName do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    # `display_name` and `email` are encrypted attributes, so AshCloak exposes
    # them as action arguments rather than plain attributes.
    display_name = argument(changeset, :display_name)
    email = argument(changeset, :email)

    if is_nil(display_name) and is_binary(email) and email != "" do
      Ash.Changeset.set_argument(changeset, :display_name, email)
    else
      changeset
    end
  end

  defp argument(changeset, field) do
    case Ash.Changeset.fetch_argument(changeset, field) do
      {:ok, value} -> value
      :error -> nil
    end
  end
end
