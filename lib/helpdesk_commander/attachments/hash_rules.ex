defmodule HelpdeskCommander.Attachments.HashRules do
  @moduledoc """
  添付ファイルの SHA256 許可・拒否リスト（HC-24）。

  - 拒否（deny）は許可（allow）より優先する。全体ルールと会社ルールの両方を評価する
  - `add/4` は同じスコープ・SHA256 のルールがあれば action と note を更新する
  - ルール変更と判定結果は監査ログ（`Logger` の `attachment_hash_rules` メタデータ）に残す
  """

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.AttachmentHashRule

  require Ash.Query
  require Logger

  @type action :: :allow | :deny
  @type decision :: action() | nil

  @doc "会社に適用されるルール（全体 + 会社）を返す。"
  @spec list(integer() | nil) :: {:ok, [AttachmentHashRule.t()]} | {:error, term()}
  def list(company_id) do
    query =
      case company_id do
        nil -> Ash.Query.filter(AttachmentHashRule, is_nil(company_id))
        id -> Ash.Query.filter(AttachmentHashRule, company_id == ^id or is_nil(company_id))
      end

    query
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(domain: Helpdesk, authorize?: false)
  end

  @doc "SHA256 の判定。拒否が優先。ルールがなければ nil。"
  @spec decision(integer() | nil, String.t()) :: decision()
  def decision(company_id, sha256) when is_binary(sha256) do
    case list(company_id) do
      {:ok, rules} ->
        actions =
          rules
          |> Enum.filter(&(&1.sha256 == sha256))
          |> Enum.map(& &1.action)

        cond do
          "deny" in actions -> :deny
          "allow" in actions -> :allow
          true -> nil
        end

      {:error, error} ->
        Logger.error("attachment_hash_rules lookup failed: #{inspect(error)}")
        nil
    end
  end

  @doc """
  ルールを追加または更新する。`company_id` が nil なら全体ルール。
  監査ログに変更内容を残す。
  """
  @spec add(integer() | nil, String.t(), action(), String.t() | nil) ::
          {:ok, AttachmentHashRule.t()} | {:error, term()}
  def add(company_id, sha256, action, note \\ nil)

  def add(company_id, sha256, action, note) when action in [:allow, :deny] do
    attrs = %{
      company_id: company_id,
      sha256: String.downcase(sha256),
      action: Atom.to_string(action),
      note: note
    }

    case find(company_id, attrs.sha256) do
      {:ok, nil} ->
        result =
          AttachmentHashRule
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create(domain: Helpdesk, authorize?: false)

        audit(:created, attrs)
        result

      {:ok, %AttachmentHashRule{} = rule} ->
        result =
          rule
          |> Ash.Changeset.for_update(:update, %{action: attrs.action, note: note})
          |> Ash.update(domain: Helpdesk, authorize?: false)

        audit(:updated, attrs)
        result

      {:error, error} ->
        {:error, error}
    end
  end

  def add(_company_id, _sha256, _action, _note), do: {:error, :invalid_action}

  @doc "ルールを削除し、監査ログに残す。"
  @spec remove(AttachmentHashRule.t()) :: :ok | {:error, term()}
  def remove(%AttachmentHashRule{} = rule) do
    case Ash.destroy(rule, domain: Helpdesk, authorize?: false) do
      :ok ->
        audit(:deleted, %{
          company_id: rule.company_id,
          sha256: rule.sha256,
          action: rule.action
        })

        :ok

      {:ok, _deleted} ->
        audit(:deleted, %{
          company_id: rule.company_id,
          sha256: rule.sha256,
          action: rule.action
        })

        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "判定結果を監査ログに残す（ingest から呼ぶ）。"
  @spec audit_decision(decision() | :cache_hit, integer() | nil, String.t()) :: :ok
  def audit_decision(decision, company_id, sha256) do
    audit(:decision, %{decision: decision, company_id: company_id, sha256: sha256})
  end

  @doc false
  @spec audit(atom(), map()) :: :ok
  def audit(event, data) do
    Logger.info("attachment_hash_rules #{event} #{inspect(data)}")
  end

  defp find(nil, sha256) do
    AttachmentHashRule
    |> Ash.Query.filter(is_nil(company_id) and sha256 == ^sha256)
    |> Ash.read_one(domain: Helpdesk, authorize?: false)
  end

  defp find(company_id, sha256) do
    AttachmentHashRule
    |> Ash.Query.filter(company_id == ^company_id and sha256 == ^sha256)
    |> Ash.read_one(domain: Helpdesk, authorize?: false)
  end
end
