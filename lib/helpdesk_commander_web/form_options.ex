defmodule HelpdeskCommanderWeb.FormOptions do
  @moduledoc false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommanderWeb.CurrentUser

  @spec load_users(User.t() | nil, boolean()) :: {:ok, [User.t()]} | {:error, term()}
  def load_users(%User{} = current_user, true), do: {:ok, [current_user]}

  def load_users(%User{company_id: company_id}, false) do
    query = filter(User, company_id == ^company_id)

    case Ash.read(query, domain: Accounts) do
      {:ok, users} ->
        {:ok,
         users
         |> Enum.reject(&(&1.role == "system" or &1.status in ~w(suspended anonymized)))
         |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})}

      {:error, error} ->
        {:error, error}
    end
  end

  def load_users(_current_user, _external_user?), do: {:ok, []}

  @spec load_products(User.t() | nil) :: {:ok, [Product.t()]} | {:error, term()}
  def load_products(%User{company_id: company_id}) do
    case Product
         |> filter(company_id == ^company_id)
         |> Ash.read(domain: Helpdesk) do
      {:ok, products} -> {:ok, Enum.sort_by(products, & &1.name, :asc)}
      {:error, error} -> {:error, error}
    end
  end

  def load_products(_current_user), do: {:ok, []}

  @spec user_options([User.t()]) :: [{String.t(), integer()}]
  def user_options(users), do: Enum.map(users, &{CurrentUser.display_label(&1), &1.id})

  @spec product_options([Product.t()]) :: [{String.t(), integer()}]
  def product_options(products), do: Enum.map(products, &{&1.name, &1.id})
end
