defmodule HelpdeskCommander.Helpdesk.TicketNotification.Preparations.ForRecipient do
  @moduledoc false

  use Ash.Resource.Preparation

  alias HelpdeskCommander.Accounts.User

  @impl Ash.Resource.Preparation
  def prepare(query, _opts, %{actor: %User{id: recipient_id}}) do
    Ash.Query.filter(query, recipient_id == ^recipient_id)
  end

  def prepare(query, _opts, _context) do
    Ash.Query.filter(query, false)
  end
end
