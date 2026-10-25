defmodule HelpdeskCommanderWeb.TaskLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: true

  import Ash.Query
  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommander.Tasks.TaskEvent

  test "authenticated user sees own company tasks", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    task = create_task!(company, title: "Visible task")

    other_company = create_company!()
    other_task = create_task!(other_company, title: "Hidden task")

    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tasks")

    assert has_element?(view, "#tasks")
    assert has_element?(view, "#task-#{task.public_id}")
    refute has_element?(view, "#task-#{other_task.public_id}")
  end

  test "user can update priority through set_priority and see the event history", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    task = create_task!(company, title: "Priority task")

    conn = log_in(conn, user)

    {:ok, view, _html} = live(conn, ~p"/tasks/#{task.public_id}")

    assert has_element?(view, "#task-priority-form")
    assert has_element?(view, "#task-priority-events-empty")

    view
    |> element("#task-priority-form")
    |> render_submit(%{"form" => %{"priority" => "high"}})

    updated = Ash.get!(Task, %{id: task.id}, domain: Tasks)
    assert updated.priority == "high"

    [event] =
      TaskEvent
      |> filter(task_id == ^task.id)
      |> Ash.read!(domain: Tasks)

    assert event.actor_id == user.id
    assert event.event_type == "priority_changed"
    assert has_element?(view, "#task-priority-events")
    assert has_element?(view, "#task-priority-event-#{event.id}")
  end

  test "user cannot view a task from another company", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)

    other_company = create_company!()
    other_task = create_task!(other_company, title: "Other company task")

    conn = log_in(conn, user)

    assert {:error, {:live_redirect, %{to: "/tasks"}}} = live(conn, ~p"/tasks/#{other_task.public_id}")
  end

  test "user can create a task", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    assignee = create_user!(company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tasks/new")

    view
    |> form("#task-form",
      form: %{
        "title" => "New task",
        "description" => "Task details",
        "status" => "in_progress",
        "priority" => "high",
        "due_date" => "2026-11-01",
        "assignee_id" => to_string(assignee.id)
      }
    )
    |> render_submit()

    task =
      Task
      |> filter(company_id == ^company.id)
      |> Ash.read_one!(domain: Tasks)

    assert task.title == "New task"
    assert task.description == "Task details"
    assert task.status == "in_progress"
    assert task.priority == "high"
    assert task.assignee_id == assignee.id
    assert task.company_id == company.id

    assert_redirect(view, ~p"/tasks/#{task.public_id}")
  end

  test "user can edit a task", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    assignee = create_user!(company)
    task = create_task!(company, title: "Original")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tasks/#{task.public_id}")

    view
    |> form("#task-edit-form",
      form: %{
        "title" => "Updated",
        "description" => "Updated description",
        "status" => "done",
        "due_date" => "2026-11-02",
        "assignee_id" => to_string(assignee.id)
      }
    )
    |> render_submit()

    updated = Ash.get!(Task, %{id: task.id}, domain: Tasks)

    assert updated.title == "Updated"
    assert updated.description == "Updated description"
    assert updated.status == "done"
    assert updated.due_date == ~D[2026-11-02]
    assert updated.assignee_id == assignee.id
    assert has_element?(view, "#task-edit-form")
  end

  test "user can delete a task", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)
    task = create_task!(company, title: "Delete me")

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tasks/#{task.public_id}")

    render_click(view, "delete", %{})

    assert_redirect(view, ~p"/tasks")
    assert {:error, %Ash.Error.Invalid{}} = Ash.get(Task, %{id: task.id}, domain: Tasks)
  end

  test "blank task title is rejected", %{conn: conn} do
    company = create_company!()
    user = create_user!(company)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tasks/new")

    view
    |> form("#task-form", form: %{"title" => "   "})
    |> render_submit()

    assert has_element?(view, "#task-form")
    assert Ash.read!(Task, domain: Tasks) == []
  end

  test "unauthenticated user is redirected to sign in", %{conn: conn} do
    company = create_company!()
    task = create_task!(company, title: "Private task")

    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tasks")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/tasks/#{task.public_id}")
  end

  test "external user is redirected away from tasks", %{conn: conn} do
    company = create_company!()
    external = create_user!(company, role: "customer")

    conn = log_in(conn, external)

    assert {:error, {:redirect, %{to: "/tickets"}}} = live(conn, ~p"/tasks")
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(%Company{id: company_id}, opts \\ []) do
    email = Keyword.get(opts, :email, "user+#{System.unique_integer([:positive])}@example.com")
    status = Keyword.get(opts, :status, "active")
    role = Keyword.get(opts, :role, "user")

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Test User",
      role: role,
      status: status,
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_task!(%Company{id: company_id}, opts) do
    Task
    |> Ash.Changeset.for_create(:create, %{
      title: Keyword.fetch!(opts, :title),
      description: Keyword.get(opts, :description, "Task description"),
      priority: Keyword.get(opts, :priority, "medium"),
      company_id: company_id
    })
    |> Ash.create!(domain: Tasks)
  end

  defp unique_company_code do
    suffix =
      System.unique_integer([:positive])
      |> rem(900_000)
      |> Kernel.+(100_000)
      |> Integer.to_string()

    "A-#{suffix}"
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
