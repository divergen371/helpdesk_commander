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

  test "trims subject and body and rejects blank values" do
    user = create_user!()
    product = create_product!(user.company_id)

    inquiry =
      Inquiry
      |> Ash.Changeset.for_create(:create, %{
        subject: "  Need help  ",
        body: "  Something broke  ",
        product_id: product.id,
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    assert inquiry.subject == "Need help"
    assert inquiry.body == "Something broke"

    assert {:error, _error} =
             Inquiry
             |> Ash.Changeset.for_create(:create, %{
               subject: "   ",
               body: "Something broke",
               product_id: product.id,
               requester_id: user.id
             })
             |> Ash.create(domain: Helpdesk)
  end

  test "rejects a product from another company" do
    user = create_user!()
    other_company = create_company!()
    other_product = create_product!(other_company.id)

    assert {:error, _error} =
             Inquiry
             |> Ash.Changeset.for_create(:create, %{
               subject: "Cross tenant",
               body: "Should be rejected",
               product_id: other_product.id,
               requester_id: user.id
             })
             |> Ash.create(domain: Helpdesk)
  end

  defp create_company! do
    HelpdeskCommander.Accounts.Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
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

  defp create_product!(company_id) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Product #{System.unique_integer([:positive])}",
      company_id: company_id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
