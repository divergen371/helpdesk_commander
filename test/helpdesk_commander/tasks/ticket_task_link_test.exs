defmodule HelpdeskCommander.Tasks.TicketTaskLinkTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task
  alias HelpdeskCommander.Tasks.TicketTaskLink

  test "links a ticket and task in the same company" do
    company = create_company!()
    user = create_user!(company)
    ticket = create_ticket!(user)
    task = create_task!(company, "Task")

    link =
      TicketTaskLink
      |> Ash.Changeset.for_create(:create, %{ticket_id: ticket.id, task_id: task.id})
      |> Ash.create!(domain: Tasks)

    assert link.company_id == company.id
    assert link.relation_type == "related"
  end

  test "rejects links across companies" do
    company = create_company!()
    user = create_user!(company)
    ticket = create_ticket!(user)

    other_company = create_company!()
    other_task = create_task!(other_company, "Other task")

    assert {:error, _error} =
             TicketTaskLink
             |> Ash.Changeset.for_create(:create, %{
               ticket_id: ticket.id,
               task_id: other_task.id
             })
             |> Ash.create(domain: Tasks)
  end

  test "rejects duplicate links" do
    company = create_company!()
    user = create_user!(company)
    ticket = create_ticket!(user)
    task = create_task!(company, "Task")

    params = %{ticket_id: ticket.id, task_id: task.id}

    TicketTaskLink
    |> Ash.Changeset.for_create(:create, params)
    |> Ash.create!(domain: Tasks)

    assert {:error, _error} =
             TicketTaskLink
             |> Ash.Changeset.for_create(:create, params)
             |> Ash.create(domain: Tasks)
  end

  test "deleting a ticket or task removes the link" do
    company = create_company!()
    user = create_user!(company)
    ticket = create_ticket!(user)
    task = create_task!(company, "Task")

    _link =
      TicketTaskLink
      |> Ash.Changeset.for_create(:create, %{ticket_id: ticket.id, task_id: task.id})
      |> Ash.create!(domain: Tasks)

    assert :ok = Ash.destroy(task, domain: Tasks)
    assert Ash.read!(TicketTaskLink, domain: Tasks) == []
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "link+#{System.unique_integer([:positive])}@example.com",
      display_name: "Link User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(user) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Ticket",
      description: "Ticket",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_task!(company, title) do
    Task
    |> Ash.Changeset.for_create(:create, %{title: title, company_id: company.id})
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
end
