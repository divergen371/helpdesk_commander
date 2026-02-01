defmodule HelpdeskCommander.Support.PublicIdProperTest do
  use ExUnit.Case, async: true

  test "PropEr: public_id generator property" do
    assert :proper.quickcheck(:proper_public_id.prop_public_id(), [{:to_file, :user}])
  end
end
