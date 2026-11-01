defmodule HelpdeskCommander.TenancyTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task

  test "tenant reads only return rows for that company" do
    company_a = create_company!()
    company_b = create_company!()
    user_a = create_user!(company_a)
    user_b = create_user!(company_b)
    _ticket_a = create_ticket!(company_a, user_a)
    _ticket_b = create_ticket!(company_b, user_b)

    tickets = Ash.read!(Ticket, domain: Helpdesk, tenant: company_a.id)

    assert Enum.map(tickets, & &1.company_id) == [company_a.id]
  end

  test "actor reads are scoped to the actor company without an explicit tenant" do
    company_a = create_company!()
    company_b = create_company!()
    user_a = create_user!(company_a)
    user_b = create_user!(company_b)
    _ticket_a = create_ticket!(company_a, user_a)
    _ticket_b = create_ticket!(company_b, user_b)

    tickets = Ash.read!(Ticket, domain: Helpdesk, actor: user_a)

    assert Enum.map(tickets, & &1.company_id) == [company_a.id]
  end

  test "domain reads are scoped by tenant" do
    company_a = create_company!()
    company_b = create_company!()
    user_a = create_user!(company_a)
    user_b = create_user!(company_b)
    _ticket_a = create_ticket!(company_a, user_a)
    _ticket_b = create_ticket!(company_b, user_b)
    _task_a = create_task!(company_a)
    _task_b = create_task!(company_b)

    assert {:ok, %{tickets: tickets, total_count: 1}} =
             Helpdesk.list_tickets(company_a.id, user_a, false, %{}, 1, 20)

    assert Enum.all?(tickets, &(&1.company_id == company_a.id))

    assert {:ok, tasks} = Tasks.list_tasks(company_a.id, actor: user_a)
    assert Enum.all?(tasks, &(&1.company_id == company_a.id))

    assert {:ok, users} = Accounts.list_users(company_a.id)
    assert Enum.all?(users, &(&1.company_id == company_a.id))
  end

  test "cross-company create is rejected" do
    company_a = create_company!()
    company_b = create_company!()
    user_a = create_user!(company_a)

    assert {:error, error} =
             Product
             |> Ash.Changeset.for_create(:create, %{
               name: "Other company product",
               company_id: company_b.id
             })
             |> Ash.create(domain: Helpdesk, actor: user_a)

    assert Exception.message(error) =~ "他の会社のデータは変更できません"
  end

  test "cross-company update is rejected" do
    company_a = create_company!()
    company_b = create_company!()
    user_a = create_user!(company_a)
    product_b = create_product!(company_b)

    assert {:error, error} =
             product_b
             |> Ash.Changeset.for_update(:update, %{name: "Changed"})
             |> Ash.update(domain: Helpdesk, actor: user_a)

    assert Exception.message(error) =~ "他の会社のデータは変更できません"
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Tenant Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "tenant+#{System.unique_integer([:positive])}@example.com",
      display_name: "Tenant User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Tenant Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_ticket!(company, user) do
    product = create_product!(company)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Tenant Ticket",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_task!(company) do
    Task
    |> Ash.Changeset.for_create(:create, %{
      title: "Tenant Task #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Tasks)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
