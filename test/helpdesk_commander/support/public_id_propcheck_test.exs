defmodule HelpdeskCommander.Support.PublicIdPropCheckTest do
  use ExUnit.Case, async: true
  use PropCheck

  property "propcheck: public_id generator property" do
    forall half <- integer(1, 32) do
      len = half * 2
      id = HelpdeskCommander.Support.PublicId.generate(len)
      byte_size(id) == len and String.match?(id, ~r/^[0-9a-f]+$/)
    end
  end

  property "propcheck: public_id rejects odd lengths" do
    forall half <- integer(0, 32) do
      len = half * 2 + 1

      assert_raise ArgumentError, fn ->
        HelpdeskCommander.Support.PublicId.generate(len)
      end

      true
    end
  end

  property "propcheck: public_id rejects non-positive lengths" do
    forall len <- integer(-32, 0) do
      assert_raise FunctionClauseError, fn ->
        HelpdeskCommander.Support.PublicId.generate(len)
      end

      true
    end
  end
end
