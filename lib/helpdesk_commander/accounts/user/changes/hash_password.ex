defmodule HelpdeskCommander.Accounts.User.Changes.HashPassword do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    password = Ash.Changeset.get_argument(changeset, :password)
    confirmation = Ash.Changeset.get_argument(changeset, :password_confirmation)

    cond do
      is_nil(password) ->
        changeset

      password != confirmation ->
        Ash.Changeset.add_error(changeset,
          field: :password_confirmation,
          message: "パスワードが一致しません"
        )

      true ->
        hashed = Bcrypt.hash_pwd_salt(password)
        Ash.Changeset.change_attribute(changeset, :password_hash, hashed)
    end
  end
end
