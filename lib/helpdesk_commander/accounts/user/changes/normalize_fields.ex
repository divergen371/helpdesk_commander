defmodule HelpdeskCommander.Accounts.User.Changes.NormalizeFields do
  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    changeset
    |> normalize(:email, &String.downcase/1)
    |> normalize(:login_id, &String.downcase/1)
    |> normalize(:display_name, &String.trim/1)
  end

  # AshCloak rewrites accepted encrypted attributes into arguments, so prefer the
  # argument and fall back to the attribute for plain attributes such as login_id.
  defp normalize(changeset, field, fun) do
    case Ash.Changeset.fetch_argument(changeset, field) do
      {:ok, value} when is_binary(value) ->
        Ash.Changeset.set_argument(changeset, field, value |> String.trim() |> fun.())

      :error ->
        normalize_attribute(changeset, field, fun)

      _value ->
        changeset
    end
  end

  defp normalize_attribute(changeset, field, fun) do
    # Encrypted attributes become calculations (no backing attribute), so only
    # normalize attributes that still exist on the resource.
    if Ash.Resource.Info.attribute(changeset.resource, field) do
      normalize_existing_attribute(changeset, field, fun)
    else
      changeset
    end
  end

  defp normalize_existing_attribute(changeset, field, fun) do
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
