defmodule HelpdeskCommander.Workers.NotificationCooldownTest do
  use HelpdeskCommander.DataCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Workers.CreateTicketNotificationsWorker

  test "notifications are created again after the cooldown expires" do
    original = Application.get_env(:helpdesk_commander, :notification_cooldown_seconds)

    on_exit(fn ->
      Application.put_env(:helpdesk_commander, :notification_cooldown_seconds, original)
    end)

    Application.put_env(:helpdesk_commander, :notification_cooldown_seconds, 0)

    requester = create_user!("user")
    admin = create_user!("admin")
    ticket = create_ticket!(requester)

    args = %{
      notification_type: "ticket_resolved_review_required",
      title: "検証待ちチケット",
      body: "確認してください",
      company_id: requester.company_id,
      ticket_id: ticket.id,
      actor_id: requester.id
    }

    assert :ok = perform_job(CreateTicketNotificationsWorker, args)
    assert :ok = perform_job(CreateTicketNotificationsWorker, args)

    notifications =
      TicketNotification
      |> filter(ticket_id == ^ticket.id and recipient_id == ^admin.id)
      |> Ash.read!(domain: Helpdesk, actor: admin)

    assert length(notifications) == 2
  end

  defp create_user!(role) do
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "cooldown+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Cooldown #{role}",
      role: role,
      status: "active",
      company_id: company.id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_ticket!(user) do
    product =
      Product
      |> Ash.Changeset.for_create(:create, %{
        name: "Cooldown Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Cooldown Ticket",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
