defmodule HelpdeskCommander.Accounts.User.Changes.DefaultDisplayName do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    display_name = Ash.Changeset.get_attribute(changeset, :display_name)
    email = Ash.Changeset.get_attribute(changeset, :email)

    if is_nil(display_name) and is_binary(email) and email != "" do
      Ash.Changeset.change_attribute(changeset, :display_name, email)
    else
      changeset
    end
  end
end
