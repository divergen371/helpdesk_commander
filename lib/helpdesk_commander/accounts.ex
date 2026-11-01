defmodule HelpdeskCommander.Accounts do
  @moduledoc false

  use Ash.Domain

  import Ash.Query

  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User

  resources do
    resource HelpdeskCommander.Accounts.Company
    resource HelpdeskCommander.Accounts.User
  end

  @spec get_user(integer()) :: {:ok, User.t()} | {:error, term()}
  def get_user(id), do: User.get_user(id)

  @spec get_company(integer()) :: {:ok, Company.t() | nil} | {:error, term()}
  def get_company(id), do: Ash.get(Company, id)

  @spec list_users(integer()) :: {:ok, [User.t()]} | {:error, term()}
  def list_users(company_id) do
    User
    |> filter(company_id == ^company_id)
    |> Ash.read(domain: __MODULE__)
  end

  @spec list_pending_users(integer()) :: {:ok, [User.t()]} | {:error, term()}
  def list_pending_users(company_id) do
    User
    |> filter(company_id == ^company_id and status == "pending")
    |> Ash.read(domain: __MODULE__)
  end

  @spec create_user(map(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def create_user(params, opts \\ []), do: User.create_user(params, opts)

  @spec update_user(User.t(), map(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def update_user(user, params, opts \\ []),
    do: user |> Ash.Changeset.for_update(:update, params) |> Ash.update(Keyword.put(opts, :domain, __MODULE__))

  @spec approve_user(User.t(), keyword()) :: {:ok, User.t()} | {:error, term()}
  def approve_user(user, opts \\ []),
    do: user |> Ash.Changeset.for_update(:approve, %{}) |> Ash.update(Keyword.put(opts, :domain, __MODULE__))
end
