defmodule HelpdeskCommanderWeb.CurrentUser do
  @moduledoc false

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Support.Error, as: ErrorLog

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

  @spec suspended?(User.t() | nil) :: boolean()
  def suspended?(%User{status: "suspended"}), do: true
  def suspended?(_user), do: false

  @spec anonymized?(User.t() | nil) :: boolean()
  def anonymized?(%User{status: "anonymized"}), do: true
  def anonymized?(_user), do: false

  @spec display_label(User.t()) :: String.t()
  def display_label(%User{status: "anonymized"}), do: "削除済みユーザー"
  def display_label(%User{role: "system"}), do: "System"

  def display_label(%User{status: "suspended", display_name: name}),
    do: "#{name}（無効）"

  def display_label(%User{display_name: name, email: email}),
    do: "#{name} <#{email}>"

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
          {:ok, %User{} = user} ->
            user

          {:ok, nil} ->
            nil

          {:error, error} ->
            ErrorLog.log_warn("current_user.fetch", error, user_id: id)
            nil
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
