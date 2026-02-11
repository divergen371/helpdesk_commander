defmodule HelpdeskCommander.Helpdesk.InquiryTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  test "creating inquiry creates a ticket and links requester" do
    user = create_user!()
    product = create_product!(user.company_id)

    inquiry =
      Inquiry
      |> Ash.Changeset.for_create(:create, %{
        subject: "Need help",
        body: "Something broke",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    ticket = Ash.get!(Ticket, %{id: inquiry.ticket_id}, domain: Helpdesk)

    assert ticket.subject == "Need help"
    assert ticket.description == "Something broke"
    assert ticket.requester_id == user.id
    assert ticket.product_id == product.id
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

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
