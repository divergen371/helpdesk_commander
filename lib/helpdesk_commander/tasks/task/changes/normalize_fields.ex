defmodule HelpdeskCommander.Tasks.Task.Changes.NormalizeFields do
  @moduledoc false

  use Ash.Resource.Change

  @impl Ash.Resource.Change
  def change(changeset, _opts, _context) do
    changeset
    |> trim(:title)
    |> trim(:description)
  end

  defp trim(changeset, field) do
    case Ash.Changeset.get_attribute(changeset, field) do
      value when is_binary(value) ->
        Ash.Changeset.change_attribute(changeset, field, String.trim(value))

      _value ->
        changeset
    end
  end
end
