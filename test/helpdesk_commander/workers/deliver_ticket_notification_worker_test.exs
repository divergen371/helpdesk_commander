defmodule HelpdeskCommander.Workers.DeliverTicketNotificationWorkerTest do
  use HelpdeskCommander.DataCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo
  import Swoosh.TestAssertions

  import Ash.Query

  import Plug.Conn
  import Req.Test, only: [stub: 2]

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Helpdesk.TicketNotification
  alias HelpdeskCommander.Notifications.External
  alias HelpdeskCommander.Workers.CreateTicketNotificationsWorker
  alias HelpdeskCommander.Workers.DeliverTicketNotificationWorker

  setup do
    original = Application.get_env(:helpdesk_commander, External)

    on_exit(fn ->
      Application.put_env(:helpdesk_commander, External, original)
    end)

    :ok
  end

  test "emails a notification once and records the timestamp" do
    configure(email_enabled: true, chat_enabled: false)
    {_recipient, notification} = create_notification!()

    assert :ok = perform_job(DeliverTicketNotificationWorker, %{notification_id: notification.id})

    assert_email_sent(fn email ->
      assert email.subject == notification.title
    end)

    reloaded = reload!(notification.id)
    assert reloaded.email_sent_at != nil

    assert :ok = perform_job(DeliverTicketNotificationWorker, %{notification_id: notification.id})
    assert_no_email_sent()
  end

  test "posts a notification to the chat webhook once" do
    configure(
      email_enabled: false,
      chat_enabled: true,
      chat_webhook_url: "https://chat.test/hook",
      chat_req_options: [plug: {Req.Test, __MODULE__}]
    )

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    stub(__MODULE__, fn conn ->
      Agent.update(counter, &(&1 + 1))
      send_resp(conn, 200, "ok")
    end)

    {_recipient, notification} = create_notification!()

    assert :ok = perform_job(DeliverTicketNotificationWorker, %{notification_id: notification.id})
    assert Agent.get(counter, & &1) == 1

    reloaded = reload!(notification.id)
    assert reloaded.chat_sent_at != nil

    assert :ok = perform_job(DeliverTicketNotificationWorker, %{notification_id: notification.id})
    assert Agent.get(counter, & &1) == 1
  end

  test "enqueues external delivery only for newly created notifications" do
    configure(chat_enabled: true, chat_webhook_url: "https://chat.test/hook", email_enabled: false)

    {_recipient, _notification} = create_notification_for_worker!()

    args = %{
      notification_type: "ticket_resolved_review_required",
      title: "検証待ちチケット",
      body: "確認してください",
      company_id: Accounts.Auth.default_company!().id,
      ticket_id: create_ticket_for_worker!().id,
      actor_id: nil
    }

    assert :ok = perform_job(CreateTicketNotificationsWorker, args)
    assert :ok = perform_job(CreateTicketNotificationsWorker, args)

    deliveries = all_enqueued(worker: DeliverTicketNotificationWorker)
    assert length(deliveries) == 1
  end

  defp configure(opts) do
    Application.put_env(:helpdesk_commander, External, opts)
  end

  defp create_notification! do
    recipient = create_user!("admin")
    ticket = create_ticket!(recipient)

    notification =
      TicketNotification
      |> Ash.Changeset.for_create(:create, %{
        notification_type: "test",
        title: "外部通知テスト",
        body: "通知本文",
        company_id: ticket.company_id,
        ticket_id: ticket.id,
        recipient_id: recipient.id
      })
      |> Ash.create!(domain: Helpdesk)

    {recipient, notification}
  end

  defp create_notification_for_worker! do
    recipient = create_user!("admin")
    ticket = create_ticket!(recipient)
    {recipient, ticket}
  end

  defp create_ticket_for_worker! do
    user = create_user!("user")
    create_ticket!(user)
  end

  defp reload!(id) do
    TicketNotification
    |> filter(id == ^id)
    |> Ash.read_one!(domain: Helpdesk, authorize?: false)
  end

  defp create_user!(role) do
    company = Accounts.Auth.default_company!()

    User
    |> Ash.Changeset.for_create(:create, %{
      email: "delivery+#{role}+#{System.unique_integer([:positive])}@example.com",
      display_name: "Delivery #{role}",
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
        name: "Delivery Product #{System.unique_integer([:positive])}",
        company_id: user.company_id
      })
      |> Ash.create!(domain: Helpdesk)

    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Delivery Ticket",
      product_id: product.id,
      requester_id: user.id
    })
    |> Ash.create!(domain: Helpdesk)
  end
end
