defmodule HelpdeskCommander.Helpdesk.TicketNotificationPropCheckTest do
  use HelpdeskCommander.DataCase, async: true
  use PropCheck

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification

  property "propcheck: mark_read sets read_at and is monotonic" do
    forall times <- integer(1, 3) do
      notification = create_notification!()

      {last_read_at, _notification} =
        Enum.reduce(1..times, {nil, notification}, fn _step, {prev_read_at, current} ->
          updated =
            current
            |> Ash.Changeset.for_update(:mark_read, %{})
            |> Ash.update!(domain: Helpdesk)

          if prev_read_at != nil do
            assert DateTime.compare(updated.read_at, prev_read_at) in [:eq, :gt]
          end

          {updated.read_at, updated}
        end)

      assert last_read_at != nil
    end
  end

  defp create_notification! do
    user = create_user!()
    ticket = create_ticket!(user)

    TicketNotification
    |> Ash.Changeset.for_create(:create, %{
      notification_type: "propcheck_read",
      title: "既読テスト",
      body: "read_atテスト",
      company_id: user.company_id,
      ticket_id: ticket.id,
      recipient_id: user.id
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
