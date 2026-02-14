defmodule HelpdeskCommander.Helpdesk.TicketAuthorizationPropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  property "propcheck: non-privileged users cannot set verified/closed" do
    forall [role <- elements(["user", "system"]), target <- elements(["verified", "closed"])] do
      user = create_user!(role)
      ticket = create_ticket!(user)

      resolved =
        ticket
        |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
        |> Ash.update!(domain: Helpdesk)

      assert {:error, _error} =
               resolved
               |> Ash.Changeset.for_update(:set_status, %{status: target, actor_id: user.id})
               |> Ash.update(domain: Helpdesk)

      true
    end
  end

  defp create_user!(role) do
    email = "auth+#{role}+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Auth User",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Authorization Test",
      description: "Authorization Test",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
