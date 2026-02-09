defmodule HelpdeskCommander.Accounts.User.Changes.NormalizeFields do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    changeset
    |> normalize(:email, &String.downcase/1)
    |> normalize(:login_id, &String.downcase/1)
    |> normalize(:display_name, &String.trim/1)
  end

  defp normalize(changeset, field, fun) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      value when is_binary(value) ->
        Ash.Changeset.change_attribute(changeset, field, value |> String.trim() |> fun.())

      _value ->
        changeset
    end
  end
end
