defmodule HelpdeskCommander.RateLimiter do
  @moduledoc """
  Rate limiter backend powered by Hammer (ETS).
  """

  use Hammer, backend: :ets
end
