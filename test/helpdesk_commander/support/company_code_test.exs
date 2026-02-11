defmodule HelpdeskCommander.Support.CompanyCodeTest do
  use ExUnit.Case, async: true

  alias HelpdeskCommander.Support.CompanyCode

  test "normalize uppercases and trims" do
    assert {:ok, "A-123456"} = CompanyCode.normalize(" a-123456 ")
  end

  test "normalize rejects invalid format" do
    assert {:error, :invalid_format} = CompanyCode.normalize("invalid")
  end

  test "hash returns binary" do
    assert {:ok, hashed} = CompanyCode.hash("A-123456")
    assert is_binary(hashed)
    assert byte_size(hashed) == 32
  end

  test "hash! raises on invalid format" do
    assert_raise ArgumentError, fn ->
      CompanyCode.hash!("bad")
    end
  end
end
