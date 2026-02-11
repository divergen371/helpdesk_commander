defmodule HelpdeskCommander.Repo.Migrations.UpdateTicketStatuses do
  use Ecto.Migration

  def change do
    execute("UPDATE tickets SET status = 'triage' WHERE status = 'open'")
    execute("UPDATE tickets SET status = 'waiting' WHERE status = 'pending'")
  end
end
