defmodule HelpdeskCommander.PoliciesTest do
  use HelpdeskCommander.DataCase, async: true

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Conversation
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketLink
  alias HelpdeskCommander.Tasks
  alias HelpdeskCommander.Tasks.Task

  test "task updates are limited to internal users in the company" do
    company = create_company!()
    internal = create_user!(company, "user")
    external = create_user!(company, "customer")
    other_company_user = create_user!(create_company!(), "user")
    task = create_task!(company)

    assert {:ok, updated} =
             task
             |> Ash.Changeset.for_update(:update, %{title: "Updated"})
             |> Ash.update(domain: Tasks, actor: internal)

    assert updated.title == "Updated"

    assert {:error, %Ash.Error.Forbidden{}} =
             task
             |> Ash.Changeset.for_update(:update, %{title: "Nope"})
             |> Ash.update(domain: Tasks, actor: external)

    assert {:error, %Ash.Error.Forbidden{}} =
             task
             |> Ash.Changeset.for_update(:update, %{title: "Nope"})
             |> Ash.update(domain: Tasks, actor: other_company_user)
  end

  test "only the sender can edit a message and admins can delete it" do
    company = create_company!()
    sender = create_user!(company, "user")
    other = create_user!(company, "user")
    admin = create_user!(company, "admin")
    message = create_message!(company, sender)

    assert {:ok, edited} =
             Helpdesk.edit_message(message, %{body: "updated"}, actor: sender)

    assert edited.body == "updated"

    assert {:error, %Ash.Error.Forbidden{}} =
             Helpdesk.edit_message(message, %{body: "nope"}, actor: other)

    assert {:ok, deleted} = Helpdesk.soft_delete_message(message, actor: admin)
    assert deleted.deleted_at != nil

    assert {:error, %Ash.Error.Forbidden{}} =
             Helpdesk.soft_delete_message(edited, actor: other)
  end

  test "ticket links can only be created by internal users in the company" do
    company = create_company!()
    internal = create_user!(company, "user")
    external = create_user!(company, "customer")
    other_company_user = create_user!(create_company!(), "user")

    assert {:ok, %TicketLink{}} =
             create_link(
               create_ticket!(company, internal),
               create_ticket!(company, internal),
               internal
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             create_link(
               create_ticket!(company, external),
               create_ticket!(company, external),
               external
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             create_link(
               create_ticket!(company, internal),
               create_ticket!(company, internal),
               other_company_user
             )
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company, role) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "policy+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Policy #{role}",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_task!(company) do
    Task
    |> Ash.Changeset.for_create(:create, %{
      title: "Policy Task",
      company_id: company.id
    })
    |> Ash.create!(domain: Tasks)
  end

  defp create_message!(company, sender) do
    ticket = create_ticket!(company, sender)

    conversation =
      Conversation
      |> filter(ticket_id == ^ticket.id and kind == "internal_public")
      |> Ash.read_one!(domain: Helpdesk)

    ConversationMessage
    |> Ash.Changeset.for_create(:create, %{
      body: "Policy message",
      conversation_id: conversation.id,
      sender_id: sender.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_link(first, second, actor) do
    TicketLink
    |> Ash.Changeset.for_create(:create, %{
      ticket_id: first.id,
      related_ticket_id: second.id,
      relation_type: "related",
      created_by_id: actor.id
    })
    |> Ash.create(domain: Helpdesk, actor: actor)
  end

  defp create_ticket!(company, requester) do
    product = create_product!(company)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Policy Ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Policy Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
