defmodule HelpdeskCommander.Helpdesk.Ticket.Checks.ActorPrivileged do
  use Ash.Policy.SimpleCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  @impl Ash.Policy.Check
  def describe(_opts), do: "actor is admin or leader"

  @impl Ash.Policy.SimpleCheck
  def match?(%User{} = actor, _context, _opts) do
    {:ok, Authorization.privileged_role?(actor)}
  end

  def match?(_actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    actor_id = Ash.Changeset.get_argument(changeset, :actor_id)

    case fetch_actor(actor_id) do
      {:ok, %User{} = actor} -> {:ok, Authorization.privileged_role?(actor)}
      _result -> {:ok, false}
    end
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  defp fetch_actor(nil), do: {:error, :missing_actor}

  defp fetch_actor(actor_id) do
    Ash.get(User, %{id: actor_id}, domain: Accounts)
  end
end
