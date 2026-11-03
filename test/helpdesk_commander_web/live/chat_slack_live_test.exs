defmodule HelpdeskCommanderWeb.ChatSlackLiveTest do
  use HelpdeskCommanderWeb.ConnCase, async: false
  use Oban.Testing, repo: HelpdeskCommander.Repo

  import Phoenix.LiveViewTest

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Chat.Slack
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Workers.PublishChatMessageWorker

  test "enqueues Slack publishing only for public messages", %{conn: conn} do
    company = create_company!()
    user = create_user!(company.id)
    product = create_product!(company)
    ticket = create_ticket!(product, user)

    Application.put_env(:helpdesk_commander, Slack,
      bot_token: "xoxb-test",
      channel_id: "C1",
      signing_secret: "secret"
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, Slack) end)

    conn = log_in(conn, user)
    {:ok, view, _html} = live(conn, ~p"/tickets/#{ticket.public_id}")

    view
    |> form("#ticket-message-form-public",
      public_message: %{"body" => "公開メッセージ", "sender_id" => to_string(user.id)}
    )
    |> render_submit()

    assert_enqueued(worker: PublishChatMessageWorker)

    view
    |> form("#ticket-message-form-private", private_message: %{"body" => "内部メモ"})
    |> render_submit()

    assert length(all_enqueued(worker: PublishChatMessageWorker)) == 1
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Slack Live ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Live Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "slack-live+#{System.unique_integer([:positive])}@example.com",
      display_name: "Slack Live",
      role: "admin",
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Live Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end

  defp log_in(conn, %User{id: id}) do
    Plug.Test.init_test_session(conn, %{user_id: id})
  end
end
