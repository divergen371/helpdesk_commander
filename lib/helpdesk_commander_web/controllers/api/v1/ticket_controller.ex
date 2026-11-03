defmodule HelpdeskCommanderWeb.Api.V1.TicketController do
  @moduledoc """
  API v1 のチケット CRUD。

  会社境界は actor と tenant で強制する。外部ユーザーは自分が依頼者のチケットのみ
  参照・操作できる。優先度・担当者の確定は Ash ポリシーに従う。
  """

  use HelpdeskCommanderWeb, :controller

  alias HelpdeskCommander.Accounts.User
  alias HelpdeskCommander.Authorization
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.Ticket
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  action_fallback HelpdeskCommanderWeb.Api.FallbackController

  @statuses ["new", "triage", "in_progress", "waiting", "resolved", "verified", "closed"]
  @priorities ["p1", "p2", "p3", "p4"]
  @types ["question", "incident", "request"]
  @sorts ["newest", "oldest", "priority", "status"]
  @page_size 20

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    user = conn.assigns.current_user
    external? = conn.assigns.current_user_external?
    filters = parse_filters(params)
    page = parse_page(params)

    case Helpdesk.list_tickets(user.company_id, user, external?, filters, page, @page_size) do
      {:ok, %{tickets: tickets, total_count: total_count, has_next?: has_next?}} ->
        json(conn, %{
          tickets: Enum.map(tickets, &ticket_json/1),
          meta: %{
            page: page,
            page_size: @page_size,
            total_count: total_count,
            has_next?: has_next?
          }
        })

      {:error, error} ->
        ErrorLog.log_error("api.tickets.index", error, user_id: user.id)
        {:error, error}
    end
  end

  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"ticket" => params}) do
    user = conn.assigns.current_user
    params = normalize_create_params(params, user)

    case Helpdesk.create_ticket(params, actor: user, tenant: user.company_id) do
      {:ok, ticket} ->
        conn
        |> put_status(201)
        |> json(%{ticket: ticket_json(ticket)})

      {:error, error} ->
        {:error, error}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{code: "validation_failed", message: "ticket オブジェクトが必要です", fields: %{}}
    })
  end

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"public_id" => public_id}) do
    user = conn.assigns.current_user

    with {:ok, ticket} <- load_ticket(public_id),
         :ok <- authorize_ticket(ticket, user),
         {:ok, ticket} <- Ash.load(ticket, [:product, :assignee], domain: Helpdesk, tenant: ticket.company_id) do
      json(conn, %{ticket: ticket_json(ticket)})
    end
  end

  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"public_id" => public_id, "ticket" => params}) do
    user = conn.assigns.current_user

    with {:ok, ticket} <- load_ticket(public_id),
         :ok <- authorize_ticket(ticket, user),
         params <- normalize_update_params(params) do
      case Helpdesk.update_ticket(ticket, params, actor: user, tenant: ticket.company_id) do
        {:ok, updated} ->
          json(conn, %{ticket: ticket_json(updated)})

        {:error, error} ->
          {:error, error}
      end
    end
  end

  def update(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{code: "validation_failed", message: "ticket オブジェクトが必要です", fields: %{}}
    })
  end

  @spec set_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_status(conn, %{"public_id" => public_id, "ticket" => %{"status" => status}}) do
    user = conn.assigns.current_user

    with {:ok, ticket} <- load_ticket(public_id),
         :ok <- authorize_ticket(ticket, user),
         true <- status in @statuses || {:error, :invalid_status} do
      case Helpdesk.set_ticket_status(ticket, %{status: status, actor_id: user.id},
             actor: user,
             tenant: ticket.company_id
           ) do
        {:ok, updated} ->
          json(conn, %{ticket: ticket_json(updated)})

        {:error, error} ->
          {:error, error}
      end
    else
      {:error, :invalid_status} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{code: "validation_failed", message: "不正なステータスです", fields: %{"status" => ["許可されていません"]}}
        })

      other ->
        other
    end
  end

  def set_status(conn, _params) do
    conn
    |> put_status(422)
    |> json(%{
      error: %{code: "validation_failed", message: "ticket.status が必要です", fields: %{}}
    })
  end

  @spec messages(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def messages(conn, %{"public_id" => public_id} = params) do
    user = conn.assigns.current_user

    with {:ok, ticket} <- load_ticket(public_id),
         :ok <- authorize_ticket(ticket, user),
         {:ok, conversation} <- Helpdesk.ensure_conversation(ticket, "internal_public"),
         {:ok, {messages, _has_more?, _oldest}} <-
           Helpdesk.list_messages(conversation.id, nil, parse_limit(params),
             tenant: ticket.company_id,
             actor: user
           ) do
      json(conn, %{messages: Enum.map(messages, &message_json/1)})
    end
  end

  defp load_ticket(public_id) do
    case Helpdesk.get_ticket_by_public_id(public_id) do
      {:ok, %Ticket{} = ticket} -> {:ok, ticket}
      {:ok, nil} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp authorize_ticket(ticket, user) do
    cond do
      ticket.visibility_scope == "global" ->
        :ok

      Authorization.external?(user) ->
        if Authorization.same_company?(user, ticket.company_id) and
             ticket.requester_id == user.id do
          :ok
        else
          {:error, :forbidden}
        end

      Authorization.same_company?(user, ticket.company_id) ->
        :ok

      true ->
        {:error, :forbidden}
    end
  end

  defp normalize_create_params(params, %User{} = user) do
    params = stringify_keys(params)

    allowed = [
      "subject",
      "description",
      "type",
      "priority",
      "impact",
      "urgency",
      "product_id",
      "requester_id",
      "assignee_id"
    ]

    taken =
      params
      |> Map.take(allowed)
      |> Map.put("status", "new")

    if Authorization.external?(user) do
      Map.put(taken, "requester_id", user.id)
    else
      Map.put_new(taken, "requester_id", user.id)
    end
  end

  defp normalize_update_params(params) do
    allowed = [
      "subject",
      "description",
      "type",
      "priority",
      "impact",
      "urgency",
      "assignee_id",
      "lock_version"
    ]

    normalized = stringify_keys(params)
    Map.take(normalized, allowed)
  end

  defp stringify_keys(params) when is_map(params) do
    Map.new(params, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_filters(params) do
    %{
      q: presence(params["q"]),
      status: allow(params["status"], @statuses),
      priority: allow(params["priority"], @priorities),
      type: allow(params["type"], @types),
      assignee_id: normalize_assignee(params["assignee_id"]),
      sort: allow(params["sort"], @sorts) || "newest"
    }
  end

  defp parse_page(params) do
    case params["page"] |> to_string() |> Integer.parse() do
      {page, _rest} when page > 0 -> page
      _result -> 1
    end
  end

  defp parse_limit(params) do
    case params["limit"] |> to_string() |> Integer.parse() do
      {limit, _rest} when limit > 0 and limit <= 100 -> limit
      _result -> 20
    end
  end

  defp normalize_assignee("unassigned"), do: "unassigned"
  defp normalize_assignee(nil), do: nil
  defp normalize_assignee(""), do: nil

  defp normalize_assignee(value) do
    case Integer.parse(value) do
      {_id, _rest} -> value
      :error -> nil
    end
  end

  defp allow(value, allowed) do
    if value in allowed, do: value, else: nil
  end

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_value), do: nil

  defp ticket_json(ticket) do
    %{
      public_id: ticket.public_id,
      subject: ticket.subject,
      description: ticket.description,
      type: ticket.type,
      status: ticket.status,
      priority: ticket.priority,
      priority_source: ticket.priority_source,
      impact: ticket.impact,
      urgency: ticket.urgency,
      visibility_scope: ticket.visibility_scope,
      lock_version: ticket.lock_version,
      product_id: ticket.product_id,
      requester_id: ticket.requester_id,
      assignee_id: ticket.assignee_id,
      inserted_at: ticket.inserted_at,
      updated_at: ticket.updated_at
    }
  end

  defp message_json(message) do
    %{
      id: message.id,
      body: message.body,
      message_type: message.message_type,
      body_format: message.body_format,
      sender_id: message.sender_id,
      inserted_at: message.inserted_at
    }
  end
end
