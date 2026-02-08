defmodule HelpdeskCommander.Helpdesk do
  @moduledoc false

  use Ash.Domain

  resources do
    resource HelpdeskCommander.Helpdesk.Inquiry
    resource HelpdeskCommander.Helpdesk.Ticket
    resource HelpdeskCommander.Helpdesk.TicketMessage
  end
end
