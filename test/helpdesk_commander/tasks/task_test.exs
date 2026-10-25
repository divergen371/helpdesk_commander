defmodule HelpdeskCommander.Tasks.TaskTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommander.Tasks.TaskEvent

  test "set_priority updates the task and records an event" do
    user = create_user!()

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Initial task", company_id: user.company_id})
      |> Ash.create!(domain: Tasks)

    updated =
      task
      |> Ash.Changeset.for_update(:set_priority, %{actor_id: user.id, priority: "high"})
      |> Ash.update!(domain: Tasks)

    assert updated.priority == "high"

    [event] =
      TaskEvent
      |> filter(task_id == ^task.id)
      |> Ash.read!(domain: Tasks)

    assert event.event_type == "priority_changed"
    assert event.actor_id == user.id
    assert (Map.get(event.data, "field") || Map.get(event.data, :field)) == "priority"
    assert (Map.get(event.data, "from") || Map.get(event.data, :from)) == "medium"
    assert (Map.get(event.data, "to") || Map.get(event.data, :to)) == "high"
  end

  test "set_priority requires an actor and does not record an event on failure" do
    user = create_user!()

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Initial task", company_id: user.company_id})
      |> Ash.create!(domain: Tasks)

    assert {:error, _error} =
             task
             |> Ash.Changeset.for_update(:set_priority, %{priority: "high"})
             |> Ash.update(domain: Tasks)

    events =
      TaskEvent
      |> filter(task_id == ^task.id)
      |> Ash.read!(domain: Tasks)

    assert events == []
  end

  test "regular update rejects priority changes to preserve history" do
    user = create_user!()

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Initial task", company_id: user.company_id})
      |> Ash.create!(domain: Tasks)

    assert {:error, %Ash.Error.Invalid{}} =
             task
             |> Ash.Changeset.for_update(:update, %{priority: "low"})
             |> Ash.update(domain: Tasks)

    reloaded = Ash.get!(Task, %{id: task.id}, domain: Tasks)
    assert reloaded.priority == "medium"

    events =
      TaskEvent
      |> filter(task_id == ^task.id)
      |> Ash.read!(domain: Tasks)

    assert events == []
  end

  test "set_priority is forbidden across companies" do
    company = create_company!()

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Tenant task", company_id: company.id})
      |> Ash.create!(domain: Tasks)

    other_company = create_company!()
    other_user = create_user_in_company!(other_company)

    assert {:error, _error} =
             task
             |> Ash.Changeset.for_update(:set_priority, %{
               actor_id: other_user.id,
               priority: "high"
             })
             |> Ash.update(domain: Tasks)

    assert TaskEvent
           |> filter(task_id == ^task.id)
           |> Ash.read!(domain: Tasks) == []
  end

  test "assignee must belong to the task company" do
    company = create_company!()
    user = create_user_in_company!(company)

    other_company = create_company!()
    other_user = create_user_in_company!(other_company)

    assert {:error, _error} =
             Task
             |> Ash.Changeset.for_create(:create, %{
               title: "Invalid assignee",
               company_id: company.id,
               assignee_id: other_user.id
             })
             |> Ash.create(domain: Tasks)

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Valid task", company_id: company.id})
      |> Ash.create!(domain: Tasks)

    assert {:ok, updated} =
             task
             |> Ash.Changeset.for_update(:update, %{assignee_id: user.id})
             |> Ash.update(domain: Tasks)

    assert updated.assignee_id == user.id
  end

  test "deleting a task removes its priority events" do
    user = create_user!()

    task =
      Task
      |> Ash.Changeset.for_create(:create, %{title: "Deletable", company_id: user.company_id})
      |> Ash.create!(domain: Tasks)

    task
    |> Ash.Changeset.for_update(:set_priority, %{actor_id: user.id, priority: "high"})
    |> Ash.update!(domain: Tasks)

    assert :ok = Ash.destroy(task, domain: Tasks)

    assert {:error, %Ash.Error.Invalid{}} = Ash.get(Task, %{id: task.id}, domain: Tasks)

    assert TaskEvent
           |> filter(task_id == ^task.id)
           |> Ash.read!(domain: Tasks) == []
  end

  defp create_company! do
    HelpdeskCommander.Accounts.Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user_in_company!(company) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "test+#{System.unique_integer([:positive])}@example.com",
      display_name: "Test User",
      company_id: company.id,
      status: "active"
    })
    |> Ash.create!(domain: Accounts)
  end

  defp unique_company_code do
    suffix =
      System.unique_integer([:positive])
      |> rem(900_000)
      |> Kernel.+(100_000)
      |> Integer.to_string()

    "A-#{suffix}"
  end

  defp create_user! do
    email = "test+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      company_id: company.id,
      status: "active"
    })
    |> Ash.create!(domain: Accounts)
  end
end
