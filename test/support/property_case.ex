defmodule HelpdeskCommander.PropertyCase do
  @moduledoc """
  Shared helpers for property-based tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnitProperties
      import StreamData
    end
  end
end
