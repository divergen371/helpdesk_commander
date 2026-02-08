defmodule HelpdeskCommander.PropertyCaseTest do
  use HelpdeskCommander.PropertyCase, async: true

  property "identity property holds" do
    check all(value <- integer()) do
      assert value == value
    end
  end
end
