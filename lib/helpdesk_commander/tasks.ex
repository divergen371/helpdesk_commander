defmodule HelpdeskCommander.Tasks do
  @moduledoc false

  use Ash.Domain

  resources do
    resource HelpdeskCommander.Tasks.Task
  end
end
