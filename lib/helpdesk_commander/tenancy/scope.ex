defmodule HelpdeskCommander.Tenancy.Scope do
  @moduledoc """
  Read preparation that scopes a query to the current tenant or actor company.

  Ash multitenancy already filters when a tenant is supplied. This preparation
  also covers callers that only pass an actor, so a forgotten tenant cannot
  expose another company's rows.
  """

  use Ash.Resource.Preparation

  alias HelpdeskCommander.Accounts.User

  @impl Ash.Resource.Preparation
  def prepare(query, _opts, %{tenant: tenant}) when is_integer(tenant) do
    Ash.Query.filter(query, company_id == ^tenant)
  end

  def prepare(query, _opts, %{actor: %User{company_id: company_id}}) do
    Ash.Query.filter(query, company_id == ^company_id)
  end

  def prepare(query, _opts, _context), do: query
end
