defmodule HelpdeskCommander.Helpdesk.TicketRelationsTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketGraph
  alias HelpdeskCommander.Helpdesk.TicketRelations

  test "creates and deletes a link and builds graph data" do
    company = create_company!()
    user = create_user!(company)
    root = create_ticket!(user, "Root")
    related = create_ticket!(user, "Related")

    assert {:ok, link} = TicketRelations.create_link(root, related.id, "blocks", user)

    assert {:ok, [entry]} = TicketRelations.list_links(root)
    assert entry.direction == :outgoing
    assert entry.ticket.id == related.id

    assert {:ok, %{nodes: nodes, edges: [edge]}} = TicketGraph.build(root)

    assert Enum.map(nodes, & &1["id"]) |> Enum.sort() ==
             Enum.sort([root.public_id, related.public_id])

    assert edge["source"] == root.public_id
    assert edge["target"] == related.public_id
    assert edge["relation"] == "blocks"

    assert :ok = TicketRelations.delete_link(root, link.id)
    assert Ash.read!(Helpdesk.TicketLink, domain: Helpdesk) == []
  end

  test "rejects links across companies and self links" do
    company = create_company!()
    user = create_user!(company)
    root = create_ticket!(user, "Root")

    other_company = create_company!()
    other_user = create_user!(other_company)
    other_ticket = create_ticket!(other_user, "Other")

    assert {:error, :different_company} =
             TicketRelations.create_link(root, other_ticket.id, "related", user)

    assert {:error, :invalid_relation} =
             TicketRelations.create_link(root, root.id, "related", user)
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
      email: "relations+#{System.unique_integer([:positive])}@example.com",
      display_name: "Relations User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(user, subject) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: subject,
      description: subject,
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
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
