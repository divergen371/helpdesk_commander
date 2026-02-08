defmodule HelpdeskCommander.Helpdesk.InquiryTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Inquiry
  alias HelpdeskCommander.Helpdesk.Ticket

  test "creating inquiry creates a ticket and links requester" do
    user = create_user!()

    inquiry =
      Inquiry
      |> Ash.Changeset.for_create(:create, %{
        subject: "Need help",
        body: "Something broke",
        requester_id: user.id
      })
      |> Ash.create!(domain: Helpdesk)

    ticket = Ash.get!(Ticket, %{id: inquiry.ticket_id}, domain: Helpdesk)

    assert ticket.subject == "Need help"
    assert ticket.description == "Something broke"
    assert ticket.requester_id == user.id
  end

  defp create_user! do
    email = "test+#{System.unique_integer([:positive])}@example.com"

    User
    |> Ash.Changeset.for_create(:create, %{email: email, name: "Test User"})
    |> Ash.create!(domain: Accounts)
  end
end
