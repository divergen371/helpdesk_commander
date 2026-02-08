defmodule HelpdeskCommander.DataCaseTest do
  use HelpdeskCommander.DataCase, async: true

  test "errors_on formats placeholders" do
    changeset =
      {%{}, %{name: :string}}
      |> Ecto.Changeset.cast(%{name: "hi"}, [:name])
      |> Ecto.Changeset.validate_length(:name, min: 3)

    assert HelpdeskCommander.DataCase.errors_on(changeset) == %{
             name: ["should be at least 3 character(s)"]
           }
  end
end
