defmodule HelpdeskCommanderWeb.SlackControllerTest do
  use HelpdeskCommanderWeb.ConnCase, async: false

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Chat.Slack
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ChatMessageLink
  alias HelpdeskCommander.Helpdesk.Product
  alias HelpdeskCommander.Helpdesk.Ticket

  @secret "controller-secret"

  setup do
    company = create_company!()
    user = create_user!(company.id)
    product = create_product!(company)
    ticket = create_ticket!(product, user)

    Application.put_env(:helpdesk_commander, Slack,
      bot_token: "xoxb-test",
      channel_id: "C1",
      signing_secret: @secret,
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:helpdesk_commander, Slack) end)

    %{company: company, user: user, ticket: ticket}
  end

  test "answers Slack URL verification with the challenge", %{conn: conn} do
    raw = ~s({"type":"url_verification","challenge":"abc123"})

    conn =
      conn
      |> json_conn()
      |> signed_post(raw)

    assert json_response(conn, 200) == %{"challenge" => "abc123"}
  end

  test "rejects requests with an invalid signature", %{conn: conn} do
    raw = ~s({"type":"url_verification","challenge":"abc123"})

    conn =
      conn
      |> json_conn()
      |> put_req_header("x-slack-request-timestamp", Integer.to_string(System.system_time(:second)))
      |> put_req_header("x-slack-signature", "v0=invalid")
      |> post("/integrations/slack/events", raw)

    assert response(conn, 401) == "invalid signature"
  end

  test "imports a thread reply from Slack", %{conn: conn, company: company, user: user, ticket: ticket} do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"ok" => true, "channel" => "C1", "ts" => "111.222"})
    end)

    published = create_message!(ticket, user, "元のメッセージ")
    assert {:ok, :published} = Slack.publish(ticket, published)

    event = %{
      "type" => "event_callback",
      "event" => %{
        "type" => "message",
        "channel" => "C1",
        "thread_ts" => "111.222",
        "ts" => "333.444",
        "text" => "Slack の返信",
        "user" => "U123"
      }
    }

    raw = Jason.encode!(event)

    conn =
      conn
      |> json_conn()
      |> signed_post(raw)

    assert response(conn, 200) == "ok"

    assert {:ok, [_link]} =
             ChatMessageLink
             |> filter(direction == "inbound")
             |> Ash.read(domain: Helpdesk, tenant: company.id)

    # Slack の再送でも増えない。
    conn
    |> recycle()
    |> json_conn()
    |> signed_post(raw)
    |> response(200)

    assert length(Ash.read!(ChatMessageLink, domain: Helpdesk, tenant: company.id)) == 2
  end

  test "ignores bot messages", %{conn: conn} do
    event = %{
      "type" => "event_callback",
      "event" => %{
        "type" => "message",
        "bot_id" => "B1",
        "channel" => "C1",
        "thread_ts" => "111.222",
        "ts" => "333.444",
        "text" => "bot"
      }
    }

    conn =
      conn
      |> json_conn()
      |> signed_post(Jason.encode!(event))

    assert response(conn, 200) == "ok"
  end

  defp signed_post(conn, raw) do
    timestamp = Integer.to_string(System.system_time(:second))
    signature = "v0=" <> hmac(@secret, "v0:#{timestamp}:#{raw}")

    conn
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post("/integrations/slack/events", raw)
  end

  defp json_conn(conn), do: put_req_header(conn, "content-type", "application/json")

  defp hmac(secret, data) do
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
  end

  defp create_message!(ticket, user, body) do
    {:ok, conversation} = Helpdesk.ensure_conversation(ticket, "internal_public")

    {:ok, message} =
      Helpdesk.create_message(%{
        conversation_id: conversation.id,
        sender_id: user.id,
        body: body,
        message_type: "message",
        body_format: "plain"
      })

    message
  end

  defp create_ticket!(product, requester) do
    Ticket
    |> Ash.Changeset.for_create(:create, %{
      subject: "Slack controller ticket",
      product_id: product.id,
      requester_id: requester.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp create_company! do
    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Controller Company #{System.unique_integer([:positive])}",
      company_code: unique_company_code()
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_user!(company_id) do
    User
    |> Ash.Changeset.for_create(:create, %{
      email: "slack-controller+#{System.unique_integer([:positive])}@example.com",
      display_name: "Slack Controller",
      role: "admin",
      status: "active",
      company_id: company_id
    })
    |> Ash.create!(domain: Accounts)
  end

  defp create_product!(company) do
    Product
    |> Ash.Changeset.for_create(:create, %{
      name: "Slack Controller Product #{System.unique_integer([:positive])}",
      company_id: company.id
    })
    |> Ash.create!(domain: Helpdesk)
  end

  defp unique_company_code do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)
    "A-#{String.pad_leading(suffix, 6, "0")}"
  end
end
