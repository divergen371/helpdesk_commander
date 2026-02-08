defmodule HelpdeskCommander.Types.BigIntTest do
  use ExUnit.Case, async: true

  test "handles nil input and dump" do
    assert {:ok, nil} = HelpdeskCommander.Types.BigInt.cast_input(nil, [])
    assert {:ok, nil} = HelpdeskCommander.Types.BigInt.dump_to_native(nil, [])
  end
end
