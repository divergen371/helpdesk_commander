defmodule HelpdeskCommander.Support.PublicIdTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Support.PublicId

  test "generate uses default length" do
    public_id = PublicId.generate()

    assert byte_size(public_id) == 16
    assert public_id =~ ~r/^[0-9a-f]+$/
  end

  test "generate raises on odd length" do
    assert_raise ArgumentError, "public_id length must be an even number", fn ->
      PublicId.generate(15)
    end
  end
end
