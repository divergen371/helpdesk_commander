defmodule HelpdeskCommander.Helpdesk do
  @moduledoc false

  use Ash.Domain

  resources do
    resource HelpdeskCommander.Helpdesk.Ticket
  end
end
