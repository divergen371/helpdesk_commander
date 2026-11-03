# Slack 連携は複数リソースと HTTP クライアントを束ねるため依存数が増える。個別に許可する。
# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
defmodule HelpdeskCommander.Chat.Slack do
  @moduledoc """
  Slack との双方向チャット連携。

  公開メッセージはチケットごとの Slack スレッドへ投稿し、スレッド返信は
  公開会話へ取り込む。認証情報は環境変数から設定する。

  環境変数:
  - `SLACK_BOT_TOKEN` - chat.postMessage を呼ぶ Bot Token
  - `SLACK_SIGNING_SECRET` - Events API の署名検証
  - `SLACK_CHAT_CHANNEL_ID` - 投稿先チャンネル
  """

  import Ash.Query

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ChatMessageLink
  alias HelpdeskCommander.Helpdesk.ChatThread
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.PiiHash
  alias HelpdeskCommander.Workers.PublishChatMessageWorker

  @config_key :helpdesk_commander
  @default_api_base "https://slack.com/api"
  @provider "slack"
  @max_text_length 3_900

  @spec enabled?() :: boolean()
  def enabled? do
    present?(bot_token()) and present?(channel_id())
  end

  @spec inbound_enabled?() :: boolean()
  def inbound_enabled?, do: present?(signing_secret())

  @spec bot_token() :: String.t() | nil
  def bot_token, do: Keyword.get(config(), :bot_token)

  @spec signing_secret() :: String.t() | nil
  def signing_secret, do: Keyword.get(config(), :signing_secret)

  @spec channel_id() :: String.t() | nil
  def channel_id, do: Keyword.get(config(), :channel_id)

  @spec api_base() :: String.t()
  def api_base, do: Keyword.get(config(), :api_base, @default_api_base)

  @spec req_options() :: keyword()
  def req_options, do: Keyword.get(config(), :req_options, [])

  @doc "公開メッセージを Slack へ送るジョブを積む。"
  @spec enqueue_publish(Ticket.t(), ConversationMessage.t()) ::
          {:ok, Oban.Job.t() | :skipped} | {:error, term()}
  def enqueue_publish(%Ticket{} = ticket, %ConversationMessage{} = message) do
    if enabled?() and not inbound?(message) do
      %{
        "message_id" => message.id,
        "ticket_id" => ticket.id,
        "company_id" => ticket.company_id
      }
      |> PublishChatMessageWorker.new()
      |> Oban.insert()
    else
      {:ok, :skipped}
    end
  end

  @doc """
  会話メッセージを Slack に投稿する。

  既に外部リンクがある場合や Slack 由来のメッセージは送らない。
  """
  @spec publish(Ticket.t(), ConversationMessage.t()) ::
          {:ok, :published | :duplicate | :disabled | :inbound} | {:error, term()}
  def publish(%Ticket{} = ticket, %ConversationMessage{} = message) do
    cond do
      not enabled?() -> {:ok, :disabled}
      inbound?(message) -> {:ok, :inbound}
      true -> publish_once(ticket, message)
    end
  end

  @doc """
  Slack Events API のメッセージイベントを公開会話へ取り込む。

  スレッド返信のみ対象。既に取り込み済みの `ts` は無視する。
  """
  @spec ingest(map()) :: {:ok, ConversationMessage.t() | :ignored | :duplicate} | {:error, term()}
  def ingest(event) when is_map(event) do
    channel_id = event["channel"]
    thread_ts = event["thread_ts"]
    external_id = event["ts"]
    text = event["text"]

    cond do
      not is_binary(channel_id) or not is_binary(thread_ts) ->
        {:ok, :ignored}

      not is_binary(external_id) or not is_binary(text) or String.trim(text) == "" ->
        {:ok, :ignored}

      true ->
        ingest_thread_reply(channel_id, thread_ts, external_id, text, event["user"])
    end
  end

  @doc "Slack の署名ヘッダーを検証する。"
  @spec verify_signature(String.t(), String.t() | nil, String.t() | nil) :: boolean()
  def verify_signature(raw_body, timestamp, signature) do
    with secret when is_binary(secret) <- signing_secret(),
         ts when is_binary(ts) <- timestamp,
         sig when is_binary(sig) <- signature,
         {timestamp_integer, ""} <- Integer.parse(ts),
         true <- abs(System.system_time(:second) - timestamp_integer) <= 300 do
      expected = "v0=" <> hex_hmac(secret, "v0:#{ts}:#{raw_body}")
      Plug.Crypto.secure_compare(expected, sig)
    else
      _other -> false
    end
  end

  defp publish_once(ticket, message) do
    with {:ok, nil} <- message_link(message),
         {:ok, thread} <- thread_for(ticket),
         {:ok, response} <- post_message(ticket, message, thread),
         {:ok, _thread} <- ensure_thread(ticket, response, thread),
         {:ok, _link} <- create_message_link(ticket, message, response, "outbound") do
      {:ok, :published}
    else
      {:ok, %ChatMessageLink{}} -> {:ok, :duplicate}
      {:error, error} -> {:error, error}
    end
  end

  defp post_message(ticket, message, thread) do
    payload =
      maybe_put_thread(
        %{
          "channel" => channel_id(),
          "text" => truncate("[#{ticket.public_id}] #{message.body}"),
          "unfurl_links" => false
        },
        thread
      )

    url = api_base() <> "/chat.postMessage"

    options =
      [
        json: payload,
        headers: [{"authorization", "Bearer #{bot_token()}"}],
        receive_timeout: 10_000
      ] ++ req_options()

    case Req.post(url, options) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %Req.Response{body: body}} ->
        {:error, {:slack_error, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ensure_thread(ticket, response, nil) do
    channel = response["channel"] || channel_id()
    ts = response["ts"]

    if is_binary(channel) and is_binary(ts) do
      ChatThread
      |> Ash.Changeset.for_create(:create, %{
        company_id: ticket.company_id,
        ticket_id: ticket.id,
        provider: @provider,
        channel_id: channel,
        thread_ts: ts
      })
      |> Ash.create(domain: Helpdesk, tenant: ticket.company_id)
    else
      {:error, :invalid_slack_response}
    end
  end

  defp ensure_thread(_ticket, _response, %ChatThread{} = thread), do: {:ok, thread}

  defp create_message_link(ticket, message, response, direction) do
    result =
      ChatMessageLink
      |> Ash.Changeset.for_create(:create, %{
        company_id: ticket.company_id,
        conversation_message_id: message.id,
        provider: @provider,
        channel_id: response["channel"] || channel_id(),
        external_message_id: response["ts"],
        direction: direction
      })
      |> Ash.create(domain: Helpdesk, tenant: ticket.company_id)

    case result do
      {:ok, link} -> {:ok, link}
      {:error, %Ash.Error.Invalid{}} -> duplicate_link(message)
      {:error, error} -> {:error, error}
    end
  end

  defp duplicate_link(message) do
    case message_link(message) do
      {:ok, %ChatMessageLink{} = link} -> {:ok, link}
      other -> other
    end
  end

  defp message_link(message) do
    ChatMessageLink
    |> filter(conversation_message_id == ^message.id and provider == "slack")
    |> Ash.read_one(domain: Helpdesk, tenant: message.company_id)
  end

  defp thread_for(ticket) do
    ChatThread
    |> filter(ticket_id == ^ticket.id and provider == "slack")
    |> Ash.read_one(domain: Helpdesk, tenant: ticket.company_id)
  end

  defp ingest_thread_reply(channel_id, thread_ts, external_id, text, slack_user) do
    with {:ok, %ChatThread{} = thread} <- find_thread(channel_id, thread_ts),
         :ok <- ensure_not_imported(channel_id, external_id),
         {:ok, %Ticket{} = ticket} <- load_ticket(thread),
         {:ok, sender} <- system_user(ticket.company_id),
         {:ok, conversation} <- Helpdesk.ensure_conversation(ticket, "internal_public"),
         {:ok, message} <-
           create_inbound_message(ticket, conversation, sender, text, slack_user, channel_id),
         {:ok, _link} <- create_inbound_link(ticket, message, channel_id, external_id) do
      {:ok, message}
    else
      {:ok, nil} -> {:ok, :ignored}
      {:error, :duplicate} -> {:ok, :duplicate}
      {:error, error} -> {:error, error}
    end
  end

  defp ensure_not_imported(channel_id, external_id) do
    case find_inbound_link(channel_id, external_id) do
      {:ok, nil} -> :ok
      {:ok, %ChatMessageLink{}} -> {:error, :duplicate}
      {:error, error} -> {:error, error}
    end
  end

  defp find_thread(channel_id, thread_ts) do
    ChatThread
    |> filter(provider == "slack" and channel_id == ^channel_id and thread_ts == ^thread_ts)
    |> Ash.read_one(domain: Helpdesk)
  end

  defp find_inbound_link(channel_id, external_id) do
    ChatMessageLink
    |> filter(
      provider == "slack" and channel_id == ^channel_id and
        external_message_id == ^external_id
    )
    |> Ash.read_one(domain: Helpdesk)
  end

  defp load_ticket(thread) do
    Ticket
    |> filter(id == ^thread.ticket_id)
    |> Ash.read_one(domain: Helpdesk, tenant: thread.company_id)
  end

  defp create_inbound_message(ticket, conversation, sender, text, slack_user, channel_id) do
    ConversationMessage
    |> Ash.Changeset.for_create(:create, %{
      company_id: ticket.company_id,
      conversation_id: conversation.id,
      sender_id: sender.id,
      body: text,
      body_format: "plain",
      meta: %{
        "source" => "slack",
        "slack_user_id" => slack_user,
        "slack_channel_id" => channel_id
      }
    })
    |> Ash.create(domain: Helpdesk, tenant: ticket.company_id)
  end

  defp create_inbound_link(ticket, message, channel_id, external_id) do
    result =
      ChatMessageLink
      |> Ash.Changeset.for_create(:create, %{
        company_id: ticket.company_id,
        conversation_message_id: message.id,
        provider: @provider,
        channel_id: channel_id,
        external_message_id: external_id,
        direction: "inbound"
      })
      |> Ash.create(domain: Helpdesk, tenant: ticket.company_id)

    case result do
      {:ok, link} -> {:ok, link}
      {:error, %Ash.Error.Invalid{}} -> {:ok, message}
      {:error, error} -> {:error, error}
    end
  end

  defp system_user(company_id) do
    email = "slack-bridge+#{company_id}@helpdesk.local"
    email_hash = PiiHash.email(email)

    case read_system_user(company_id, email_hash) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:ok, nil} ->
        create_system_user(company_id, email)

      {:error, error} ->
        {:error, error}
    end
  end

  defp read_system_user(company_id, email_hash) do
    User
    |> filter(company_id == ^company_id and email_hash == ^email_hash)
    |> Ash.read_one(domain: Accounts, tenant: company_id)
  end

  defp create_system_user(company_id, email) do
    result =
      User
      |> Ash.Changeset.for_create(:create, %{
        company_id: company_id,
        email: email,
        display_name: "Slack Bridge",
        role: "system",
        status: "active"
      })
      |> Ash.create(domain: Accounts, tenant: company_id)

    case result do
      {:ok, user} -> {:ok, user}
      {:error, error} -> retry_system_user(company_id, email, error)
    end
  end

  defp retry_system_user(company_id, email, original_error) do
    case read_system_user(company_id, PiiHash.email(email)) do
      {:ok, %User{} = user} -> {:ok, user}
      _result -> {:error, original_error}
    end
  end

  defp inbound?(message) do
    get_in(message.meta || %{}, ["source"]) == "slack"
  end

  defp maybe_put_thread(payload, %ChatThread{thread_ts: thread_ts}) do
    Map.put(payload, "thread_ts", thread_ts)
  end

  defp maybe_put_thread(payload, _thread), do: payload

  defp truncate(text) when byte_size(text) <= @max_text_length, do: text
  defp truncate(text), do: String.slice(text, 0, @max_text_length)

  defp hex_hmac(secret, data) do
    mac = :crypto.mac(:hmac, :sha256, secret, data)
    Base.encode16(mac, case: :lower)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp config do
    Application.get_env(@config_key, __MODULE__, [])
  end
end
