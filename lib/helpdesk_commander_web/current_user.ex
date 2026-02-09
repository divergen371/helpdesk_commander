defmodule HelpdeskCommanderWeb.CurrentUser do
  @moduledoc false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User

  @external_roles ~w(customer external)
  @admin_roles ~w(admin leader)

  @spec fetch(map()) :: User.t() | nil
  def fetch(session) when is_map(session) do
    session
    |> user_id_from_session()
    |> fetch_user()
  end

  @spec external?(User.t() | nil) :: boolean()
  def external?(%User{role: role}), do: role in @external_roles
  def external?(_user), do: false

  @spec admin?(User.t() | nil) :: boolean()
  def admin?(%User{role: role}), do: role in @admin_roles
  def admin?(_user), do: false

  @spec active?(User.t() | nil) :: boolean()
  def active?(%User{status: "active"}), do: true
  def active?(_user), do: false

  defp user_id_from_session(session) do
    Map.get(session, "user_id") || Map.get(session, :user_id)
  end

  defp fetch_user(nil), do: nil

  defp fetch_user(user_id) do
    case normalize_id(user_id) do
      nil ->
        nil

      id ->
        case Ash.get(User, %{id: id}, domain: Accounts) do
          {:ok, %User{} = user} -> user
          _result -> nil
        end
    end
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, _rest} -> value
      :error -> nil
    end
  end

  defp normalize_id(_id), do: nil
end
