defmodule HelpdeskCommander.Helpdesk.Notifications do
  @moduledoc false

  import Ash.Query

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.TicketNotification

  @spec list_for(User.t()) :: {:ok, [TicketNotification.t()]} | {:error, term()}
  def list_for(%User{} = user) do
    with {:ok, notifications} <- Ash.read(TicketNotification, domain: Helpdesk, actor: user) do
      Ash.load(notifications, [:ticket], domain: Helpdesk)
    end
  end

  @spec unread_count(User.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def unread_count(%User{} = user) do
    query = filter(TicketNotification, is_nil(read_at))
    Ash.count(query, domain: Helpdesk, actor: user)
  end

  @spec mark_read(User.t(), integer()) :: {:ok, TicketNotification.t()} | {:error, term()}
  def mark_read(%User{} = user, notification_id) do
    with {:ok, %TicketNotification{} = notification} <-
           Ash.get(TicketNotification, notification_id, domain: Helpdesk, actor: user),
         {:ok, updated} <-
           notification
           |> Ash.Changeset.for_update(:mark_read, %{})
           |> Ash.update(domain: Helpdesk, actor: user) do
      {:ok, updated}
    else
      {:ok, nil} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  @spec mark_all_read(User.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def mark_all_read(%User{} = user) do
    query = filter(TicketNotification, is_nil(read_at))

    with {:ok, notifications} <- Ash.read(query, domain: Helpdesk, actor: user) do
      Enum.reduce_while(notifications, {:ok, 0}, fn notification, {:ok, count} ->
        case notification
             |> Ash.Changeset.for_update(:mark_read, %{})
             |> Ash.update(domain: Helpdesk, actor: user) do
          {:ok, _updated} -> {:cont, {:ok, count + 1}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end
end
