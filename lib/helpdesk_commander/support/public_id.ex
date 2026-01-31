defmodule HelpdeskCommander.Support.PublicId do
  @moduledoc """
  Generates public IDs for URLs (random hex).

  Default length is 16 chars (8 bytes). You can pass a larger even length
  (e.g., 32) if/when collision budget needs to increase.
  """

  @default_length 16

  @spec generate(pos_integer()) :: String.t()
  def generate(length \\ @default_length) when is_integer(length) and length > 0 do
    if rem(length, 2) != 0 do
      raise ArgumentError, "public_id length must be an even number"
    end

    length
    |> div(2)
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
