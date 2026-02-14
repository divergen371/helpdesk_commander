defmodule HelpdeskCommander.Accounts.UserStatePropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck.StateM

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User

  property "propcheck: user lifecycle follows the state model", numtests: 20, max_size: 15 do
    forall cmds <- commands(__MODULE__) do
      {_history, _state, result} = run_commands(__MODULE__, cmds)
      result == :ok
    end
  end

  @impl true
  def initial_state, do: %{user: nil, status: nil}

  @impl true
  def command(%{user: nil}) do
    elements([{:call, __MODULE__, :create_user, []}])
  end

  def command(%{user: user}) do
    elements([
      {:call, __MODULE__, :suspend_user, [user]},
      {:call, __MODULE__, :anonymize_user, [user]}
    ])
  end

  @impl true
  def precondition(%{user: nil}, {:call, __MODULE__, :create_user, []}), do: true

  def precondition(%{status: "active"}, {:call, __MODULE__, :suspend_user, [_user]}), do: true

  def precondition(%{status: status}, {:call, __MODULE__, :anonymize_user, [_user]}),
    do: status in ["active", "suspended", "anonymized"]

  def precondition(_state, _call), do: false

  @impl true
  def next_state(_state, user, {:call, __MODULE__, :create_user, []}) do
    %{user: user, status: "active"}
  end

  def next_state(state, _result, {:call, __MODULE__, :suspend_user, [_arg]}) do
    %{state | status: "suspended"}
  end

  def next_state(state, _result, {:call, __MODULE__, :anonymize_user, [_arg]}) do
    %{state | status: "anonymized"}
  end

  @impl true
  def postcondition(_state, {:call, __MODULE__, :create_user, []}, %User{} = user) do
    user.status == "active"
  end

  def postcondition(_state, {:call, __MODULE__, :suspend_user, [_user]}, %User{} = user) do
    user.status == "suspended" and user.password_hash == nil and user.suspended_at != nil
  end

  def postcondition(_state, {:call, __MODULE__, :anonymize_user, [_user]}, %User{} = user) do
    user.status == "anonymized" and
      user.email == "deleted-#{user.id}@anonymized.local" and
      user.display_name == "削除済みユーザー" and
      user.login_id == nil and
      user.password_hash == nil and
      user.anonymized_at != nil
  end

  def postcondition(_state, _call, _result), do: false

  def create_user do
    email = "propcheck+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "PropCheck User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  def suspend_user(%User{} = user) do
    user
    |> Ash.Changeset.for_update(:suspend, %{})
    |> Ash.update!(domain: Accounts)
  end

  def anonymize_user(%User{} = user) do
    user
    |> Ash.Changeset.for_update(:anonymize, %{})
    |> Ash.update!(domain: Accounts)
  end
end
