defmodule HelpdeskCommanderWeb.SlaLive.Index do
  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Helpdesk.Sla
  alias HelpdeskCommander.Support.Error, as: ErrorLog
  alias HelpdeskCommanderWeb.CurrentUser

  @impl Phoenix.LiveView
  def mount(_params, session, socket) do
    current_user = CurrentUser.fetch(session)

    if CurrentUser.admin?(current_user) do
      case Sla.list_targets(current_user.company_id) do
        {:ok, targets} ->
          {:ok,
           socket
           |> assign(:page_title, "SLA 設定")
           |> assign(:current_user, current_user)
           |> assign(:rows, build_rows(targets))}

        {:error, error} ->
          ErrorLog.log_error("sla_live.load", error, user_id: CurrentUser.id(current_user))

          {:ok,
           socket
           |> put_flash(:error, "SLA 設定の取得に失敗しました")
           |> assign(:page_title, "SLA 設定")
           |> assign(:current_user, current_user)
           |> assign(:rows, build_rows([]))}
      end
    else
      {:ok,
       socket
       |> put_flash(:error, "SLA 設定を変更する権限がありません")
       |> push_navigate(to: ~p"/")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"priority" => priority, "policy" => params}, socket) do
    case Sla.save_policy(socket.assigns.current_user.company_id, priority, params, socket.assigns.current_user) do
      {:ok, _policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{String.upcase(priority)} の SLA を保存しました")
         |> reload_rows()}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "SLA 設定を変更する権限がありません")}

      {:error, :unknown_priority} ->
        {:noreply, put_flash(socket, :error, "不明な優先度です")}

      {:error, error} ->
        ErrorLog.log_error("sla_live.save", error, priority: priority)

        {:noreply, put_flash(socket, :error, "SLA 設定の保存に失敗しました")}
    end
  end

  defp reload_rows(socket) do
    case Sla.list_targets(socket.assigns.current_user.company_id) do
      {:ok, targets} -> assign(socket, :rows, build_rows(targets))
      {:error, _error} -> socket
    end
  end

  defp build_rows(targets) do
    configured = Map.new(targets, &{&1.priority, &1})

    Enum.map(Sla.priorities(), fn priority ->
      targets = Map.get(configured, priority, %{targets: Sla.default_targets(priority)})

      %{
        priority: priority,
        source: Map.get(targets, :source, :default),
        form:
          to_form(
            %{
              "first_response_minutes" => targets.targets.first_response,
              "mitigation_minutes" => targets.targets.mitigation,
              "resolution_minutes" => targets.targets.resolution,
              "restoration_minutes" => targets.targets.restoration
            },
            as: "policy"
          )
      }
    end)
  end

  defp source_label(:configured), do: "個別設定"
  defp source_label(_source), do: "既定値"

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        SLA 設定
        <:subtitle>優先度ごとの目標時間（分）。未設定の優先度は既定値を使います。</:subtitle>
        <:actions>
          <.button navigate={~p"/"}>ダッシュボードへ</.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 gap-6">
        <div :for={row <- @rows} class="card bg-base-100 border border-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="font-semibold">{String.upcase(row.priority)}</h2>
              <span class={[
                "badge",
                row.source == :configured && "badge-success",
                row.source == :default && "badge-ghost"
              ]}>
                {source_label(row.source)}
              </span>
            </div>

            <.form
              for={row.form}
              id={"sla-form-#{row.priority}"}
              phx-submit="save"
              class="mt-4"
            >
              <input type="hidden" name="priority" value={row.priority} />

              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <.input
                  id={"sla-#{row.priority}-first-response"}
                  field={row.form[:first_response_minutes]}
                  type="number"
                  label="一次応答（分）"
                  min="1"
                />
                <.input
                  id={"sla-#{row.priority}-mitigation"}
                  field={row.form[:mitigation_minutes]}
                  type="number"
                  label="暫定対応（分）"
                  min="1"
                />
                <.input
                  id={"sla-#{row.priority}-resolution"}
                  field={row.form[:resolution_minutes]}
                  type="number"
                  label="解決（分）"
                  min="1"
                />
                <.input
                  id={"sla-#{row.priority}-restoration"}
                  field={row.form[:restoration_minutes]}
                  type="number"
                  label="復旧（分）"
                  min="1"
                />
              </div>

              <div class="mt-4 flex justify-end">
                <.button type="submit" variant="primary">保存</.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
