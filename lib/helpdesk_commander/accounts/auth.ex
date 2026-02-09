defmodule HelpdeskCommander.Accounts.Auth do
  @moduledoc false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Support.CompanyCode

  @type auth_error ::
          :invalid_credentials
          | :email_login_disabled
          | :pending_approval
          | :inactive
          | :company_not_found
          | :invalid_company_code
          | :user_not_found
          | :already_active

  @spec authenticate(String.t(), String.t(), String.t()) :: {:ok, User.t()} | {:error, auth_error()}
  def authenticate(company_code, login_or_email, password) do
    with {:ok, company} <- fetch_company(company_code),
         {:ok, user, used_email?} <- fetch_user(company.id, login_or_email),
         :ok <- ensure_email_login_allowed(user, used_email?),
         :ok <- verify_password(user, password),
         :ok <- ensure_active(user),
         {:ok, user} <- maybe_generate_login_id(user, login_or_email, used_email?) do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec register_pending_user(String.t(), String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, User.t()} | {:error, auth_error()}
  def register_pending_user(company_code, email, password, password_confirmation, display_name \\ nil) do
    with {:ok, company} <- fetch_company(company_code),
         {:ok, user} <- fetch_pending_user(company.id, email),
         {:ok, user} <- register_user(user, password, password_confirmation, display_name) do
      {:ok, user}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec approve_user(User.t()) :: {:ok, User.t()} | {:error, term()}
  def approve_user(%User{} = user) do
    user
    |> Ash.Changeset.for_update(:approve, %{})
    |> Ash.update(domain: Accounts)
  end

  @spec default_company() :: {:ok, Company.t()} | {:error, term()}
  def default_company do
    case Company |> filter(name == ^default_company_name()) |> Ash.read_one(domain: Accounts) do
      {:ok, %Company{} = company} ->
        {:ok, company}

      _result ->
        Company
        |> Ash.Changeset.for_create(:create, %{
          name: default_company_name(),
          company_code: default_company_code()
        })
        |> Ash.create(domain: Accounts)
    end
  end

  @spec default_company!() :: Company.t()

  def default_company! do
    case default_company() do
      {:ok, company} -> company
      {:error, error} -> raise error
    end
  end

  @spec default_company_name() :: String.t()

  def default_company_name, do: "Internal"

  @spec default_company_code() :: String.t()
  def default_company_code, do: "A-000001"

  defp fetch_company(company_code) do
    case CompanyCode.hash(company_code) do
      {:ok, hashed} ->
        case Company
             |> filter(company_code_hash == ^hashed)
             |> Ash.read_one(domain: Accounts) do
          {:ok, %Company{} = company} -> {:ok, company}
          _result -> {:error, :company_not_found}
        end

      {:error, :invalid_format} ->
        {:error, :invalid_company_code}
    end
  end

  defp fetch_user(company_id, login_or_email) when is_binary(login_or_email) do
    normalized = login_or_email |> String.trim() |> String.downcase()
    used_email? = String.contains?(normalized, "@")

    query =
      if used_email? do
        filter(User, company_id == ^company_id and email == ^normalized)
      else
        filter(User, company_id == ^company_id and login_id == ^normalized)
      end

    case Ash.read_one(query, domain: Accounts) do
      {:ok, %User{} = user} -> {:ok, user, used_email?}
      _result -> {:error, :invalid_credentials}
    end
  end

  defp fetch_pending_user(company_id, email) do
    normalized = email |> String.trim() |> String.downcase()

    query = filter(User, company_id == ^company_id and email == ^normalized)

    case Ash.read_one(query, domain: Accounts) do
      {:ok, %User{status: "pending"} = user} -> {:ok, user}
      {:ok, %User{}} -> {:error, :already_active}
      _result -> {:error, :user_not_found}
    end
  end

  defp register_user(user, password, password_confirmation, display_name) do
    base_params = %{
      password: password,
      password_confirmation: password_confirmation
    }

    params =
      if is_binary(display_name) and display_name != "" do
        Map.put(base_params, :display_name, display_name)
      else
        base_params
      end

    user
    |> Ash.Changeset.for_update(:register, params)
    |> Ash.update(domain: Accounts)
  end

  defp ensure_email_login_allowed(%User{login_id: nil}, true), do: :ok
  defp ensure_email_login_allowed(%User{}, true), do: {:error, :email_login_disabled}
  defp ensure_email_login_allowed(_user, false), do: :ok

  defp ensure_active(%User{status: "active"}), do: :ok
  defp ensure_active(%User{status: "pending"}), do: {:error, :pending_approval}
  defp ensure_active(%User{}), do: {:error, :inactive}

  defp verify_password(%User{password_hash: nil}, _password), do: {:error, :invalid_credentials}

  defp verify_password(%User{password_hash: hash}, password) do
    if Bcrypt.verify_pass(password, hash) do
      :ok
    else
      {:error, :invalid_credentials}
    end
  end

  defp maybe_generate_login_id(%User{login_id: nil, company_id: company_id} = user, email, true) do
    login_id = generate_login_id(company_id, email)

    user
    |> Ash.Changeset.for_update(:set_login_id, %{login_id: login_id})
    |> Ash.update(domain: Accounts)
  end

  defp maybe_generate_login_id(user, _login_or_email, _used_email?), do: {:ok, user}

  defp generate_login_id(company_id, email) do
    email
    |> String.split("@")
    |> List.first()
    |> normalize_login_id()
    |> ensure_unique_login_id(company_id, 0)
  end

  defp normalize_login_id(nil), do: fallback_login_id()

  defp normalize_login_id(local_part) do
    normalized =
      local_part
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]/, "_")
      |> String.trim("_-")

    if String.length(normalized) < 3 do
      fallback_login_id()
    else
      normalized
    end
  end

  defp fallback_login_id do
    "user#{System.unique_integer([:positive])}"
  end

  defp ensure_unique_login_id(base, company_id, attempt) when attempt < 100 do
    candidate = candidate_login_id(base, attempt)

    query = filter(User, company_id == ^company_id and login_id == ^candidate)

    case Ash.read_one(query, domain: Accounts) do
      {:ok, %User{}} -> ensure_unique_login_id(base, company_id, attempt + 1)
      _result -> candidate
    end
  end

  defp ensure_unique_login_id(base, _company_id, _attempt) do
    unique = System.unique_integer([:positive])
    candidate_login_id(base, unique)
  end

  defp candidate_login_id(base, 0), do: clamp_login_id(base)

  defp candidate_login_id(base, attempt) do
    suffix = "-#{attempt}"
    max_base = 32 - String.length(suffix)
    trimmed = base |> clamp_login_id() |> String.slice(0, max_base)
    trimmed <> suffix
  end

  defp clamp_login_id(base) do
    String.slice(base, 0, 32)
  end
end
