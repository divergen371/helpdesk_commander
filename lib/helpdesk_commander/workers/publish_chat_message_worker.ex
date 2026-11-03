defmodule HelpdeskCommander.Workers.PublishChatMessageWorker do
  @moduledoc """
  公開会話メッセージを Slack スレッドへ投稿する。

  再実行時は `ChatMessageLink` の一意制約と既存リンク確認で重複投稿を防ぐ。
  """

  use Oban.Worker,
    queue: :integrations,
    max_attempts: 5,
    unique: [period: 60, fields: [:args], keys: [:message_id]]

  import Ash.Query

  alias HelpdeskCommander.Chat.Slack
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.ConversationMessage
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, message_id} <- fetch_integer(args, "message_id"),
         {:ok, ticket_id} <- fetch_integer(args, "ticket_id"),
         {:ok, company_id} <- fetch_integer(args, "company_id"),
         {:ok, %ConversationMessage{} = message} <- load_message(message_id, company_id),
         {:ok, %Ticket{} = ticket} <- load_ticket(ticket_id, company_id),
         {:ok, _result} <- Slack.publish(ticket, message) do
      :ok
    else
      {:error, reason} = error ->
        ErrorLog.log_error("workers.publish_chat_message", reason, args: args)
        error
    end
  end

  defp load_message(id, company_id) do
    ConversationMessage
    |> filter(id == ^id)
    |> Ash.read_one(domain: Helpdesk, tenant: company_id)
    |> normalize_not_found()
  end

  defp load_ticket(id, company_id) do
    Ticket
    |> filter(id == ^id)
    |> Ash.read_one(domain: Helpdesk, tenant: company_id)
    |> normalize_not_found()
  end

  defp normalize_not_found({:ok, nil}), do: {:error, :not_found}
  defp normalize_not_found(result), do: result

  defp fetch_integer(args, key) do
    case args[key] do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _other -> {:error, {:invalid_arg, key}}
        end

      _other ->
        {:error, {:invalid_arg, key}}
    end
  end
end
