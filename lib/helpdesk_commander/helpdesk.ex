defmodule HelpdeskCommander.Helpdesk do
  @moduledoc false

  use Ash.Domain

  resources do
    resource HelpdeskCommander.Helpdesk.Conversation
    resource HelpdeskCommander.Helpdesk.ConversationMessage
    resource HelpdeskCommander.Helpdesk.Inquiry
    resource HelpdeskCommander.Helpdesk.Product
    resource HelpdeskCommander.Helpdesk.Ticket
    resource HelpdeskCommander.Helpdesk.TicketEvent
    resource HelpdeskCommander.Helpdesk.TicketLink
    resource HelpdeskCommander.Helpdesk.TicketMessage
  end
end
