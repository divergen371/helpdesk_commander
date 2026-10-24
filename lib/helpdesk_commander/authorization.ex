defmodule HelpdeskCommander.Authorization do
  @moduledoc false

  alias HelpdeskCommander.Accounts.User

  @privileged_roles ~w(admin leader)
  @external_roles ~w(customer external)

  @spec privileged_role?(User.t() | String.t() | nil) :: boolean()
  def privileged_role?(%User{role: role}), do: role in @privileged_roles
  def privileged_role?(role) when is_binary(role), do: role in @privileged_roles
  def privileged_role?(_role), do: false

  @spec external?(User.t() | String.t() | nil) :: boolean()
  def external?(%User{role: role}), do: role in @external_roles
  def external?(role) when is_binary(role), do: role in @external_roles
  def external?(_role), do: false

  @spec internal?(User.t() | String.t() | nil) :: boolean()
  def internal?(%User{} = user), do: not external?(user)
  def internal?(role) when is_binary(role), do: not external?(role)
  def internal?(_role), do: false

  @spec same_company?(User.t() | nil, integer() | nil) :: boolean()
  def same_company?(%User{company_id: company_id}, company_id), do: not is_nil(company_id)
  def same_company?(_user, _company_id), do: false

  @spec privileged_for_company?(User.t() | nil, integer() | nil) :: boolean()
  def privileged_for_company?(%User{} = user, company_id) do
    privileged_role?(user) and same_company?(user, company_id)
  end

  def privileged_for_company?(_user, _company_id), do: false
end
