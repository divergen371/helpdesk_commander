defmodule HelpdeskCommander.CacheTest do
  use ExUnit.Case, async: true

  test "put and get values from cache" do
    assert {:ok, _} = HelpdeskCommander.Cache.put(:example_key, "value")
    assert {:ok, "value"} = HelpdeskCommander.Cache.get(:example_key)
  end
end
