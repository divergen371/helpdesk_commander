defmodule HelpdeskCommander.Helpdesk.TicketNotificationTest do
  use HelpdeskCommander.DataCase, async: true

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification

  test "read only returns notifications for the actor and sorts newest first" do
    recipient = create_user!()
    other = create_user!()
    ticket = create_ticket!(recipient)

    first = create_notification!(ticket, recipient, "first")
    second = create_notification!(ticket, recipient, "second")
    _other = create_notification!(ticket, other, "other")

    notifications =
      TicketNotification
      |> Ash.read!(domain: Helpdesk, actor: recipient)

    assert Enum.map(notifications, & &1.id) == [second.id, first.id]
    assert Enum.all?(notifications, &(&1.recipient_id == recipient.id))
  end

  test "read without an actor is forbidden" do
    recipient = create_user!()
    ticket = create_ticket!(recipient)
    _notification = create_notification!(ticket, recipient, "secret")

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(TicketNotification, domain: Helpdesk)
  end

  test "mark_read is forbidden for a non-recipient" do
    recipient = create_user!()
    other = create_user!()
    ticket = create_ticket!(recipient)
    notification = create_notification!(ticket, recipient, "secret")

    assert {:error, %Ash.Error.Forbidden{}} =
             notification
             |> Ash.Changeset.for_update(:mark_read, %{})
             |> Ash.update(domain: Helpdesk, actor: other)
  end

  defp create_notification!(ticket, recipient, body) do
    TicketNotification
    |> Ash.Changeset.for_create(:create, %{
      notification_type: "test",
      title: "Test",
      body: body,
      company_id: ticket.company_id,
      ticket_id: ticket.id,
      recipient_id: recipient.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_user! do
    email = "notify+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Notify User",
      role: "user",
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(%User{} = user) do
    product = create_product!(user.company_id)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Notification Test",
      description: "Notification Test",
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
