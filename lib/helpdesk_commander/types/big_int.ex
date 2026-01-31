defmodule HelpdeskCommander.Types.BigInt do
  @moduledoc """
  Big integer type for Ash backed by Postgres `bigint`.
  """

  use Ash.Type

  @impl Ash.Type
  def storage_type(_constraints), do: :bigint

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) do
    Ecto.Type.cast(:integer, value)
  end

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) do
    Ecto.Type.load(:integer, value)
  end

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) do
    Ecto.Type.dump(:integer, value)
  end
end
