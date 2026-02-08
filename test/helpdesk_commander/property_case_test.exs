defmodule HelpdeskCommander.PropertyCaseTest do
  use HelpdeskCommander.PropertyCase, async: true

  property "integer round-trips through string conversion" do
    check all(value <- integer()) do
      assert value == value |> Integer.to_string() |> String.to_integer()
    end
  end
end
