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
      |> Ash.Changeset.for_create(:create, %{title: "Initial task"})
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

  defp create_user! do
    email = "test+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{email: email, name: "Test User"})
    |> Ash.create!(domain: Accounts)
  end
end
