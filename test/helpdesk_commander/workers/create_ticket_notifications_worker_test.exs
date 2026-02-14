defmodule HelpdeskCommander.Workers.CreateTicketNotificationsWorkerTest do
  use HelpdeskCommander.DataCase, async: true
  use Oban.Testing, repo: HelpdeskCommander.Repo

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Helpdesk.TicketVerification
  alias HelpdeskCommander.Workers.CreateTicketNotificationsWorker

  test "worker creates notifications for admin/leader and excludes actor" do
    requester = create_user!("user")
    admin = create_user!("admin")
    leader = create_user!("leader")
    _other = create_user!("user")
    ticket = create_ticket!(requester)

    assert :ok =
             perform_job(CreateTicketNotificationsWorker, %{
               notification_type: "ticket_resolved_review_required",
               title: "検証待ちチケット",
               body: "検証/承認を確認してください",
               company_id: requester.company_id,
               ticket_id: ticket.id,
               actor_id: requester.id,
               meta: %{"from" => "in_progress", "to" => "resolved"}
             })

    notifications =
      TicketNotification
      |> filter(ticket_id == ^ticket.id and notification_type == "ticket_resolved_review_required")
      |> Ash.read!(domain: Helpdesk)

    recipient_ids =
      notifications
      |> Enum.map(& &1.recipient_id)
      |> Enum.sort()

    assert recipient_ids == Enum.sort([admin.id, leader.id])
  end

  test "worker discards invalid args" do
    assert {:discard, {:invalid_string, "title"}} =
             perform_job(CreateTicketNotificationsWorker, %{
               notification_type: "ticket_resolved_review_required",
               title: "",
               body: "body",
               company_id: 1,
               ticket_id: 1
             })
  end

  test "set_status to resolved enqueues notification job" do
    user = create_user!("user")
    ticket = create_ticket!(user)

    _resolved =
      ticket
      |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
      |> Ash.update!(domain: Helpdesk)

    assert_enqueued(
      worker: CreateTicketNotificationsWorker,
      queue: :notifications,
      args: %{"notification_type" => "ticket_resolved_review_required", "ticket_id" => ticket.id}
    )
  end

  test "verification submission enqueues notification job" do
    user = create_user!("user")
    ticket = create_ticket!(user)

    _resolved =
      ticket
      |> Ash.Changeset.for_update(:set_status, %{status: "resolved", actor_id: user.id})
      |> Ash.update!(domain: Helpdesk)

    _verification =
      TicketVerification
      |> Ash.Changeset.for_create(:create, %{
        ticket_id: ticket.id,
        verifier_id: user.id,
        result: "passed",
        notes: "確認OK"
      })
      |> Ash.create!(domain: Helpdesk)

    assert_enqueued(
      worker: CreateTicketNotificationsWorker,
      queue: :notifications,
      args: %{"notification_type" => "ticket_verification_submitted", "ticket_id" => ticket.id}
    )
  end

  defp create_user!(role) do
    email = "notify+#{System.unique_integer([:positive])}@example.com"
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: email,
      display_name: "Notify User",
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
