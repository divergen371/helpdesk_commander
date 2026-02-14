defmodule HelpdeskCommander.Authorization do
  @moduledoc false

  alias HelpdeskCommander.Accounts.User

  @privileged_roles ~w(admin leader)

  @spec privileged_role?(User.t() | String.t() | nil) :: boolean()
  def privileged_role?(%User{role: role}), do: role in @privileged_roles
  def privileged_role?(role) when is_binary(role), do: role in @privileged_roles
  def privileged_role?(_role), do: false
end
