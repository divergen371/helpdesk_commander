defmodule HelpdeskCommander.Helpdesk.Ticket.Checks.StatusDoesNotRequirePrivilegedRole do
  use Ash.Policy.SimpleCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization

  @privileged_statuses ~w(verified closed)

  @impl Ash.Policy.Check
  def describe(_opts), do: "target status does not require admin or leader"

  @impl Ash.Policy.SimpleCheck
  def match?(%User{} = actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    {:ok, authorized?(actor, changeset)}
  end

  def match?(_actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    actor_id = Ash.Changeset.get_argument(changeset, :actor_id)

    case fetch_actor(actor_id) do
      {:ok, %User{} = actor} -> {:ok, authorized?(actor, changeset)}
      _result -> {:ok, false}
    end
  end

  def match?(_actor, _context, _opts), do: {:ok, false}

  defp authorized?(%User{} = actor, %Ash.Changeset{data: data} = changeset) do
    status = Ash.Changeset.get_argument(changeset, :status)

    status not in @privileged_statuses and
      Authorization.internal?(actor) and
      Authorization.same_company?(actor, Map.get(data, :company_id))
  end

  defp fetch_actor(nil), do: {:error, :missing_actor}

  defp fetch_actor(actor_id) do
    Ash.get(User, %{id: actor_id}, domain: Accounts)
  end
end
