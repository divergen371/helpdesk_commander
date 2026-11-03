defmodule HelpdeskCommander.Chat.SlackTest do
  use HelpdeskCommander.DataCase, async: false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Chat.Slack
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ChatMessageLink
  alias HelpdeskCommander.Helpdesk.ChatThread
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  setup do
    company = create_company!()
    user = create_user!(company.id)
    product = create_product!(company)
    ticket = create_ticket!(product, user)

    Application.put_env(:helpdesk_commander, Slack,
      bot_token: "xoxb-test",
      channel_id: "C1",
      signing_secret: "signing-secret",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, Slack) end)

    %{company: company, user: user, ticket: ticket}
  end

  describe "publish/2" do
    test "posts a public message once and records the thread and link", %{
      company: company,
      user: user,
      ticket: ticket
    } do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"ok" => true, "channel" => "C1", "ts" => "111.222"})
      end)

      message = create_message!(ticket, user, "こんにちは")

      assert {:ok, :published} = Slack.publish(ticket, message)

      assert {:ok, %ChatThread{} = thread} =
               ChatThread
               |> filter(ticket_id == ^ticket.id)
               |> Ash.read_one(domain: Helpdesk, tenant: company.id)

      assert thread.channel_id == "C1"
      assert thread.thread_ts == "111.222"

      assert {:ok, [link]} =
               ChatMessageLink
               |> filter(conversation_message_id == ^message.id)
               |> Ash.read(domain: Helpdesk, tenant: company.id)

      assert link.direction == "outbound"
      assert link.external_message_id == "111.222"

      assert {:ok, :duplicate} = Slack.publish(ticket, message)
      assert length(message_links(company.id)) == 1
    end

    test "does not post Slack-origin messages back", %{user: user, ticket: ticket} do
      message =
        create_message!(ticket, user, "from slack", meta: %{"source" => "slack"})

      assert {:ok, :inbound} = Slack.publish(ticket, message)
    end
  end

  describe "ingest/1" do
    test "imports a thread reply into the public conversation and deduplicates it", %{
      company: company,
      user: user,
      ticket: ticket
    } do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"ok" => true, "channel" => "C1", "ts" => "111.222"})
      end)

      published = create_message!(ticket, user, "最初の投稿")
      assert {:ok, :published} = Slack.publish(ticket, published)

      event = %{
        "channel" => "C1",
        "thread_ts" => "111.222",
        "ts" => "333.444",
        "text" => "Slack からの返信",
        "user" => "U123"
      }

      assert {:ok, %ConversationMessage{} = message} = Slack.ingest(event)
      assert message.body == "Slack からの返信"
      assert message.meta["source"] == "slack"
      assert message.meta["slack_user_id"] == "U123"

      sender = Ash.get!(User, message.sender_id, domain: Accounts, tenant: company.id)
      assert sender.role == "system"

      assert {:ok, :duplicate} = Slack.ingest(event)
      assert length(inbound_links(company.id)) == 1
    end

    test "ignores replies for unknown threads" do
      event = %{
        "channel" => "C-unknown",
        "thread_ts" => "999.999",
        "ts" => "333.444",
        "text" => "無視される返信",
        "user" => "U123"
      }

      assert {:ok, :ignored} = Slack.ingest(event)
    end
  end

  describe "verify_signature/3" do
    test "accepts a fresh signature and rejects tampering or old timestamps" do
      raw = ~s({"type":"url_verification"})
      timestamp = Integer.to_string(System.system_time(:second))
      signature = "v0=" <> hmac("signing-secret", "v0:#{timestamp}:#{raw}")

      assert Slack.verify_signature(raw, timestamp, signature)
      refute Slack.verify_signature(raw <> "x", timestamp, signature)

      old_timestamp = Integer.to_string(System.system_time(:second) - 301)
      old_signature = "v0=" <> hmac("signing-secret", "v0:#{old_timestamp}:#{raw}")
      refute Slack.verify_signature(raw, old_timestamp, old_signature)
    end
  end

  defp create_message!(ticket, user, body, opts \\ []) do
    {:ok, conversation} = Helpdesk.ensure_conversation(ticket, "internal_public")

    {:ok, message} =
      Helpdesk.create_message(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        body: body,
        message_type: "message",
        body_format: "plain",
        meta: Keyword.get(opts, :meta, %{})
      })

    message
  end

  defp message_links(company_id) do
    ChatMessageLink |> Ash.read!(domain: Helpdesk, tenant: company_id)
  end

  defp inbound_links(company_id) do
    ChatMessageLink
    |> filter(direction == "inbound")
    |> Ash.read!(domain: Helpdesk, tenant: company_id)
  end

  defp hmac(secret, data) do
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Slack ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "slack+#{System.unique_integer([:positive])}@example.com",
      display_name: "Slack User",
      role: "admin",
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
