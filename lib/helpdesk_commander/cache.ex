defmodule HelpdeskCommander.Cache do
  @moduledoc """
  In-memory cache backed by Cachex.
  """

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [[name: __MODULE__]]}
    }
  end

  @spec get(term()) :: {:ok, term()} | {:error, term()}
  def get(key) do
    Cachex.get(__MODULE__, key)
  end

  @spec put(term(), term(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def put(key, value, opts \\ []) do
    Cachex.put(__MODULE__, key, value, opts)
  end
end
