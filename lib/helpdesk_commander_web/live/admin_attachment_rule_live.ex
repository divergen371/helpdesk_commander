defmodule HelpdeskCommanderWeb.AdminAttachmentRuleLive do
  @moduledoc """
  添付ファイルの SHA256 許可・拒否リストを管理する管理者向け画面（HC-24）。
  """

  use HelpdeskCommanderWeb, :live_view

  alias HelpdeskCommander.Attachments.HashRules
  alias HelpdeskCommander.Support.Error, as: ErrorLog

  @empty_form %{"sha256" => "", "action" => "deny", "scope" => "company", "note" => ""}

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "添付ハッシュ規則")
     |> assign(:form, to_form(@empty_form, as: "rule"))
     |> load_rules()}
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"rule" => params}, socket) do
    company_id =
      if params["scope"] == "global", do: nil, else: socket.assigns.current_user.company_id

    sha256 = params |> Map.get("sha256", "") |> to_string() |> String.trim() |> String.downcase()
    action = if params["action"] == "allow", do: :allow, else: :deny
    note = blank_to_nil(params["note"])

    if Regex.match?(~r/^[a-f0-9]{64}$/, sha256) do
      case HashRules.add(company_id, sha256, action, note) do
        {:ok, _rule} ->
          {:noreply,
           socket
           |> put_flash(:info, "ハッシュ規則を保存しました")
           |> assign(:form, to_form(@empty_form, as: "rule"))
           |> load_rules()}

        {:error, error} ->
          ErrorLog.log_error("admin_attachment_rule.save", error)
          {:noreply, put_flash(socket, :error, "ハッシュ規則の保存に失敗しました")}
      end
    else
      {:noreply, put_flash(socket, :error, "SHA256 は 64 文字の 16 進で入力してください")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("delete", %{"id" => id}, socket) do
    rule = Enum.find(socket.assigns.rules, &(to_string(&1.id) == id))

    case rule && HashRules.remove(rule) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "ハッシュ規則を削除しました")
         |> load_rules()}

      _error ->
        {:noreply, put_flash(socket, :error, "ハッシュ規則の削除に失敗しました")}
    end
  end

  defp load_rules(socket) do
    case HashRules.list(socket.assigns.current_user.company_id) do
      {:ok, rules} ->
        assign(socket, :rules, rules)

      {:error, error} ->
        ErrorLog.log_error("admin_attachment_rule.load", error)
        put_flash(socket, :error, "ハッシュ規則の取得に失敗しました")
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(note) when is_binary(note), do: String.trim(note)

  defp scope_label(nil, _company_id), do: "全体"
  defp scope_label(company_id, company_id), do: "自社"
  defp scope_label(_other, _company_id), do: "他社"

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]}>
      <.header>
        添付ハッシュ規則
        <:subtitle>SHA256 の許可・拒否リスト（拒否が優先）</:subtitle>
      </.header>

      <div class="card bg-base-100 border border-base-200">
        <div class="card-body">
          <.form for={@form} id="hash-rule-form" phx-submit="save" class="grid gap-4 sm:grid-cols-2">
            <.input
              field={@form[:sha256]}
              label="SHA256"
              placeholder="64 文字の 16 進"
              required
            />
            <.input
              field={@form[:action]}
              type="select"
              label="動作"
              options={[{"拒否（即隔離）", "deny"}, {"許可（スキャン省略）", "allow"}]}
            />
            <.input
              field={@form[:scope]}
              type="select"
              label="適用範囲"
              options={[{"自社", "company"}, {"全体（全社）", "global"}]}
            />
            <.input field={@form[:note]} label="メモ" placeholder="任意" />

            <div class="sm:col-span-2 flex justify-end">
              <.button type="submit" variant="primary">保存</.button>
            </div>
          </.form>
        </div>
      </div>

      <div class="mt-6 card bg-base-100 border border-base-200">
        <div class="card-body p-0">
          <.table id="hash-rules" rows={@rules}>
            <:col :let={rule} label="SHA256"><span class="font-mono text-xs">{short_hash(rule.sha256)}</span></:col>
            <:col :let={rule} label="動作">{action_label(rule.action)}</:col>
            <:col :let={rule} label="範囲">{scope_label(rule.company_id, @current_user.company_id)}</:col>
            <:col :let={rule} label="メモ">{rule.note}</:col>
            <:action :let={rule}>
              <.button type="button" phx-click="delete" phx-value-id={rule.id}>削除</.button>
            </:action>
          </.table>
        </div>
      </div>

      <div class="mt-6">
        <.link class="link" navigate={~p"/tickets"}>← チケット一覧へ</.link>
      </div>
    </Layouts.app>
    """
  end

  defp short_hash(sha256), do: String.slice(sha256, 0, 16) <> "…"

  defp action_label("allow"), do: "許可"
  defp action_label("deny"), do: "拒否"
  defp action_label(other), do: other
end
