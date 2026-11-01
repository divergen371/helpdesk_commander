defmodule HelpdeskCommander.Repo.Migrations.AddNotificationDeliveryTimestamps do
  use Ecto.Migration

  def change do
    alter table(:ticket_notifications) do
      add :email_sent_at, :utc_datetime_usec
      add :chat_sent_at, :utc_datetime_usec
    end
  end
end
