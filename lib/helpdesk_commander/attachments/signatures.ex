defmodule HelpdeskCommander.Attachments.Signatures do
  @moduledoc """
  スキャナシグネチャの記録と鮮度判定（HC-22）。

  - `record/1` で更新結果（エンジン・版・シグネチャ日時・成否）を単一レコードに保存する
  - `freshness/0` は保存済みのシグネチャ日時（なければ最終確認日時）と
    `:attachment_signature_max_age_hours`（既定 24 時間）を比較する
  - `ensure_fresh/0` はアップロード時のゲート。`:attachment_signature_enforce` が
    true なら古い/未記録のシグネチャでアップロードを拒否し、false なら警告のみ
  """

  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.AttachmentSignature

  require Logger
  require Ash.Query

  @name "clamav"
  @default_max_age_hours 24

  @type record_attrs :: %{
          optional(:engine) => String.t() | nil,
          optional(:version) => String.t() | nil,
          optional(:signature_at) => DateTime.t() | nil,
          optional(:checked_at) => DateTime.t() | nil,
          optional(:status) => String.t(),
          optional(:last_error) => String.t() | nil
        }

  @doc "現在のシグネチャ状態。未記録なら nil。"
  @spec current() :: {:ok, AttachmentSignature.t() | nil} | {:error, term()}
  def current do
    AttachmentSignature
    |> Ash.Query.filter(name: @name)
    |> Ash.read_one(domain: Helpdesk, authorize?: false)
  end

  @doc "更新結果を保存する（単一レコードを upsert）。"
  @spec record(map()) :: {:ok, AttachmentSignature.t()} | {:error, term()}
  def record(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.put_new(:checked_at, DateTime.utc_now())
      |> Map.put_new(:status, "ok")

    case current() do
      {:ok, nil} ->
        AttachmentSignature
        |> Ash.Changeset.for_create(:create, Map.put(attrs, :name, @name))
        |> Ash.create(domain: Helpdesk, authorize?: false)

      {:ok, %AttachmentSignature{} = signature} ->
        signature
        |> Ash.Changeset.for_update(:record, attrs)
        |> Ash.update(domain: Helpdesk, authorize?: false)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  鮮度を判定する。`{:ok, :fresh | :stale | :unknown}` を返す。
  基準は `signature_at`（なければ `checked_at`）。
  """
  @spec freshness() :: {:ok, :fresh | :stale | :unknown} | {:error, Exception.t()}
  def freshness do
    case current() do
      {:ok, signature} -> {:ok, classify(signature)}
      {:error, error} -> {:error, error}
    end
  end

  defp classify(nil), do: :unknown

  defp classify(%AttachmentSignature{} = signature) do
    case signature_at(signature) do
      nil -> :unknown
      at -> if(stale?(at), do: :stale, else: :fresh)
    end
  end

  @doc """
  アップロード時のゲート。強制（`:attachment_signature_enforce`）が有効で
  鮮度が stale / unknown のときは `{:error, :signature_stale}`、それ以外は :ok。
  """
  @spec ensure_fresh() :: :ok | {:error, :signature_stale}
  def ensure_fresh do
    case freshness() do
      {:ok, :fresh} ->
        :ok

      {:ok, other} ->
        if enforce?() do
          {:error, :signature_stale}
        else
          Logger.warning("attachment scanner signatures are #{other}; uploads are not blocked")
          :ok
        end

      {:error, error} ->
        if enforce?() do
          {:error, :signature_stale}
        else
          Logger.warning("attachment scanner signature check failed: #{inspect(error)}")
          :ok
        end
    end
  end

  @doc "シグネチャが古いか（既定 24 時間）。"
  @spec stale?(DateTime.t()) :: boolean()
  def stale?(%DateTime{} = at) do
    DateTime.diff(DateTime.utc_now(), at, :hour) >= max_age_hours()
  end

  @spec max_age_hours() :: pos_integer()
  def max_age_hours do
    case Application.get_env(:helpdesk_commander, :attachment_signature_max_age_hours) do
      hours when is_integer(hours) and hours > 0 -> hours
      _other -> @default_max_age_hours
    end
  end

  defp enforce? do
    Application.get_env(:helpdesk_commander, :attachment_signature_enforce, false) == true
  end

  defp signature_at(%AttachmentSignature{signature_at: %DateTime{} = at}), do: at

  defp signature_at(%AttachmentSignature{checked_at: %DateTime{} = at}), do: at

  defp signature_at(_signature), do: nil
end
