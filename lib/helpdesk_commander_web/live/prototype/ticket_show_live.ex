defmodule HelpdeskCommanderWeb.Prototype.TicketShowLive do
  @moduledoc """
  LiveView prototype: ticket detail with
  - status update
  - 2-channel chat (public/private)
  - basic memory/latency indicators

  Uses `HelpdeskCommander.Prototype.TicketStore` (in-memory) to avoid needing
  Ash resources/migrations for this validation.
  """

  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Prototype.TicketStore

  @tick_ms 2_000

  @impl Phoenix.LiveView
  def mount(%{"id" => ticket_id}, _session, socket) do
    :ok = TicketStore.ensure_ticket(ticket_id)

    ticket = TicketStore.get_ticket(ticket_id)

    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:ticket_id, ticket_id)
      |> assign(:ticket_number, ticket.number)
      |> assign(:subject, ticket.subject)
      |> assign(:status, ticket.status)
      |> assign(:active_kind, :internal_public)
      |> assign(:connected, connected?(socket))
      |> assign(:lv_pid, inspect(self()))
      |> assign(:lv_memory_bytes, 0)
      |> assign(:last_event_us, nil)
      |> assign(:message_form, to_form(%{"body" => ""}, as: :message))
      |> stream(:public_messages, TicketStore.list_messages(ticket_id, :internal_public, 50))
      |> stream(:private_messages, TicketStore.list_messages(ticket_id, :internal_private, 50))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(HelpdeskCommander.PubSub, TicketStore.topic(ticket_id))
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("switch_kind", %{"kind" => kind}, socket) do
    kind = parse_kind!(kind)
    {:noreply, assign(socket, :active_kind, kind)}
  end

  def handle_event("send_message", %{"message" => %{"body" => body}}, socket) do
    body =
      body
      |> default_param("")
      |> String.trim()

    if body == "" do
      {:noreply, put_flash(socket, :error, "メッセージが空です")}
    else
      kind = socket.assigns.active_kind

      {us, msg} =
        :timer.tc(fn ->
          TicketStore.append_message(socket.assigns.ticket_id, kind, "you", body)
        end)

      socket =
        socket
        |> assign(:last_event_us, us)
        |> assign(:message_form, to_form(%{"body" => ""}, as: :message))

      {:noreply, stream_insert(socket, stream_name(kind), msg)}
    end
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    status =
      status
      |> default_param("")
      |> String.trim()

    if status == "" do
      {:noreply, socket}
    else
      {us, ticket} =
        :timer.tc(fn ->
          TicketStore.set_status(socket.assigns.ticket_id, status, "you")
        end)

      {:noreply, socket |> assign(:last_event_us, us) |> assign(:status, ticket.status)}
    end
  end

  def handle_event("seed", %{"kind" => kind, "count" => count}, socket) do
    kind = parse_kind!(kind)

    count =
      count
      |> default_param("200")
      |> parse_positive_integer(200)

    {us, :ok} =
      :timer.tc(fn ->
        TicketStore.seed_messages(socket.assigns.ticket_id, kind, count)
      end)

    messages = TicketStore.list_messages(socket.assigns.ticket_id, kind, 200)

    socket =
      socket
      |> assign(:last_event_us, us)
      |> stream(stream_name(kind), messages, reset: true)

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_info(:tick, socket) do
    mem = lv_memory_bytes()

    socket =
      socket
      |> assign(:connected, connected?(socket))
      |> assign(:lv_memory_bytes, mem)

    if connected?(socket) do
      Process.send_after(self(), :tick, @tick_ms)
    end

    {:noreply, socket}
  end

  def handle_info({:message, kind, msg, meta}, socket) do
    socket =
      socket
      |> assign(:status, meta.status)
      |> stream_insert(stream_name(kind), msg)

    {:noreply, socket}
  end

  def handle_info({:seeded, _kind, _count, meta}, socket) do
    # No-op: seeding triggers a reset in the requester.
    {:noreply, assign(socket, :status, meta.status)}
  end

  def handle_info({:status_changed, status, _actor, _meta}, socket) do
    {:noreply, assign(socket, :status, status)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="space-y-1">
            <h1 class="text-xl font-semibold tracking-tight">チケット詳細（プロトタイプ）</h1>
            <div class="text-sm text-base-content/70">
              <span class="font-mono">{@ticket_number}</span>
              <span class="mx-2">•</span>
              <span class="font-mono">{@ticket_id}</span>
            </div>
            <div class="text-sm">{@subject}</div>
          </div>

          <div class="rounded-box border border-base-200 bg-base-100 p-3 text-xs text-base-content/70">
            <div class="flex flex-wrap gap-x-4 gap-y-1">
              <div>
                <span class="font-semibold">connected:</span>
                {@connected}
              </div>
              <div>
                <span class="font-semibold">lv_pid:</span>
                {@lv_pid}
              </div>
              <div>
                <span class="font-semibold">lv_mem:</span>
                {format_bytes(@lv_memory_bytes)}
              </div>
              <div>
                <span class="font-semibold">last_event:</span>
                {format_us(@last_event_us)}
              </div>
            </div>
          </div>
        </div>

        <div class="card border border-base-200 bg-base-100">
          <div class="card-body space-y-6">
            <div class="flex flex-wrap items-center gap-2">
              <span class={status_badge_class(@status)}>{String.upcase(@status)}</span>

              <div class="flex flex-wrap gap-2">
                <.button phx-click="set_status" phx-value-status="new" class="btn btn-sm">new</.button>
                <.button phx-click="set_status" phx-value-status="triage" class="btn btn-sm">triage</.button>
                <.button phx-click="set_status" phx-value-status="in_progress" class="btn btn-sm">
                  in_progress
                </.button>
                <.button phx-click="set_status" phx-value-status="waiting" class="btn btn-sm">waiting</.button>
                <.button phx-click="set_status" phx-value-status="resolved" class="btn btn-sm">
                  resolved
                </.button>
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <button
                type="button"
                phx-click="switch_kind"
                phx-value-kind="internal_public"
                class={tab_class(@active_kind == :internal_public)}
              >
                公開チャット
              </button>
              <button
                type="button"
                phx-click="switch_kind"
                phx-value-kind="internal_private"
                class={tab_class(@active_kind == :internal_private)}
              >
                非公開（社内メモ）
              </button>
            </div>

            <div class="grid gap-6 lg:grid-cols-2">
              <div class="space-y-3">
                <div class="flex items-center justify-between">
                  <h2 class="text-sm font-semibold">会話</h2>
                  <div class="text-xs text-base-content/60">
                    表示は最大200件（ページングは本実装で対応）
                  </div>
                </div>

                <div class="rounded-box border border-base-200 bg-base-50/50 p-3">
                  <div
                    id="public-messages"
                    phx-update="stream"
                    class={[
                      "space-y-2 max-h-[32rem] overflow-auto",
                      @active_kind != :internal_public && "hidden"
                    ]}
                  >
                    <div class="hidden only:block text-xs text-base-content/60">No messages</div>

                    <div :for={{id, msg} <- @streams.public_messages} id={id} class="rounded-box bg-base-100 p-3">
                      <div class="flex items-baseline justify-between gap-4">
                        <div class="text-xs font-semibold">{msg.sender}</div>
                        <div class="text-[11px] text-base-content/60">{format_dt(msg.inserted_at)}</div>
                      </div>
                      <div class="mt-1 whitespace-pre-wrap break-words text-sm">{msg.body}</div>
                    </div>
                  </div>

                  <div
                    id="private-messages"
                    phx-update="stream"
                    class={[
                      "space-y-2 max-h-[32rem] overflow-auto",
                      @active_kind != :internal_private && "hidden"
                    ]}
                  >
                    <div class="hidden only:block text-xs text-base-content/60">No messages</div>

                    <div
                      :for={{id, msg} <- @streams.private_messages}
                      id={id}
                      class="rounded-box bg-base-100 p-3"
                    >
                      <div class="flex items-baseline justify-between gap-4">
                        <div class="text-xs font-semibold">{msg.sender}</div>
                        <div class="text-[11px] text-base-content/60">{format_dt(msg.inserted_at)}</div>
                      </div>
                      <div class="mt-1 whitespace-pre-wrap break-words text-sm">{msg.body}</div>
                    </div>
                  </div>
                </div>

                <div class="flex flex-wrap items-center gap-2">
                  <.button
                    phx-click="seed"
                    phx-value-kind={Atom.to_string(@active_kind)}
                    phx-value-count="200"
                    class="btn btn-sm"
                  >
                    Seed 200
                  </.button>
                  <.button
                    phx-click="seed"
                    phx-value-kind={Atom.to_string(@active_kind)}
                    phx-value-count="1000"
                    class="btn btn-sm"
                  >
                    Seed 1000
                  </.button>
                  <div class="text-xs text-base-content/60">
                    ※大量seedは初回検証用。現実はページング前提。
                  </div>
                </div>
              </div>

              <div class="space-y-3">
                <h2 class="text-sm font-semibold">送信</h2>

                <.form for={@message_form} id="ticket-message-form" phx-submit="send_message" class="space-y-3">
                  <.input
                    field={@message_form[:body]}
                    type="textarea"
                    label={message_label(@active_kind)}
                    rows="6"
                    placeholder="ヒアリング内容やメモを入力…"
                  />

                  <div class="flex items-center gap-2">
                    <.button type="submit" variant="primary">送信</.button>
                    <div class="text-xs text-base-content/60">
                      送信先: {kind_label(@active_kind)}
                    </div>
                  </div>
                </.form>

                <div class="rounded-box border border-base-200 bg-base-50/50 p-3 text-xs text-base-content/70">
                  <div class="font-semibold">このプロトタイプで見るポイント</div>
                  <ul class="mt-2 list-disc pl-5 space-y-1">
                    <li>タブ切替・送信時の体感（カクつき/遅延）</li>
                    <li>Seed 1000 時の描画/スクロール感</li>
                    <li>複数タブで同一チケットを開いた時の同期待ち受け</li>
                    <li>LV memory の増え方（右上）</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp parse_kind!("internal_public"), do: :internal_public
  defp parse_kind!("internal_private"), do: :internal_private
  defp parse_kind!(other), do: raise(ArgumentError, "unknown kind: #{inspect(other)}")

  defp stream_name(:internal_public), do: :public_messages
  defp stream_name(:internal_private), do: :private_messages

  defp kind_label(:internal_public), do: "公開"
  defp kind_label(:internal_private), do: "非公開"

  defp message_label(kind), do: "メッセージ（#{kind_label(kind)}）"

  defp tab_class(active?) do
    [
      "btn btn-sm",
      active? && "btn-primary",
      !active? && "btn-ghost"
    ]
  end

  defp status_badge_class(status) do
    base = "badge badge-lg"

    cond do
      status in ["resolved", "verified", "closed"] -> "#{base} badge-success"
      status in ["waiting"] -> "#{base} badge-warning"
      status in ["in_progress", "triage"] -> "#{base} badge-info"
      true -> "#{base} badge-ghost"
    end
  end

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp format_dt(other), do: to_string(other)

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 0 do
    kb = bytes / 1024
    formatted = :io_lib.format("~.1f KB", [kb])
    IO.iodata_to_binary(formatted)
  end

  defp format_bytes(_bytes), do: "-"

  defp format_us(nil), do: "-"
  defp format_us(us) when is_integer(us), do: "#{us}µs"

  defp lv_memory_bytes do
    case :erlang.process_info(self(), :memory) do
      {:memory, bytes} when is_integer(bytes) -> bytes
      _other -> 0
    end
  end

  defp default_param(nil, default), do: default
  defp default_param("", default), do: default
  defp default_param(value, _default), do: to_string(value)

  defp parse_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _rest} when n > 0 -> n
      _other -> default
    end
  end

  defp parse_positive_integer(_value, default), do: default
end
