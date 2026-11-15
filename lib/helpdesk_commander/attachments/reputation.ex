defmodule HelpdeskCommander.Attachments.Reputation do
  @moduledoc """
  SHA256 ハッシュのみを使った外部レピュテーション照会（HC-41）。

  - 既定は無効（グローバル設定と会社単位設定の両方が有効なときのみ照会）
  - ファイル本体は一切送信しない（SHA256 文字列のみ）
  - 同一ハッシュの再照会を DB キャッシュ（TTL 付き）で抑止する
  - API 障害・タイムアウト時は `{:error, reason}` を返し、呼び出し側で fail-open とする
  - 照会結果・キャッシュヒット・無効化・障害は監査ログ（`Logger`）に残す
  """

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Attachments.Reputation.HttpProvider
  alias HelpdeskCommander.Cache
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.AttachmentReputationCache

  require Ash.Query
  require Logger

  @default_infected_ttl_sec 86_400
  @default_unknown_ttl_sec 3_600
  @default_error_ttl_sec 60
  @default_circuit_open_sec 30

  @type check_result ::
          {:infected, String.t() | nil}
          | :unknown
          | :disabled
          | {:error, term()}

  @doc """
  会社設定とグローバル設定を確認し、有効なら SHA256 を照会する。
  無効時は外部へ一切リクエストを送らず `:disabled` を返す。
  """
  @spec check(integer(), String.t()) :: check_result()
  def check(company_id, sha256) when is_integer(company_id) and is_binary(sha256) do
    normalized = String.downcase(sha256)
    config = current_config()

    if enabled_for_company?(company_id, config) do
      lookup_with_cache(company_id, normalized, config)
    else
      audit(:disabled, %{company_id: company_id, sha256: normalized})
      :disabled
    end
  end

  @doc "グローバルの外部レピュテーション設定が有効かどうかを返す。"
  @spec global_enabled?() :: boolean()
  def global_enabled? do
    Map.get(current_config(), :enabled, false) == true
  end

  @doc "会社単位の外部レピュテーション有効/無効を取得する。"
  @spec company_enabled?(integer()) :: boolean()
  def company_enabled?(company_id) when is_integer(company_id) do
    case fetch_company(company_id) do
      {:ok, %Company{external_reputation_enabled: true}} -> true
      _other -> false
    end
  end

  @doc "会社単位の外部レピュテーション有効/無効を更新し、監査ログに残す。"
  @spec set_company_enabled(integer(), boolean()) :: {:ok, Company.t()} | {:error, term()}
  def set_company_enabled(company_id, enabled) when is_integer(company_id) and is_boolean(enabled) do
    with {:ok, %Company{} = company} <- fetch_company(company_id),
         {:ok, updated} <-
           company
           |> Ash.Changeset.for_update(:update, %{external_reputation_enabled: enabled})
           |> Ash.update(domain: Accounts, authorize?: false) do
      audit(:company_setting_updated, %{company_id: company_id, enabled: enabled})
      {:ok, updated}
    else
      {:ok, nil} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp enabled_for_company?(company_id, config) do
    Map.get(config, :enabled, false) == true and company_enabled?(company_id)
  end

  defp lookup_with_cache(company_id, sha256, config) do
    now = DateTime.utc_now()

    case fetch_valid_cache(sha256, now) do
      {:ok, %AttachmentReputationCache{verdict: "infected", detail: detail, provider: provider}} ->
        audit(:cache_hit, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider,
          verdict: :infected,
          cached: true,
          detail: detail
        })

        {:infected, detail}

      {:ok, %AttachmentReputationCache{verdict: "unknown", provider: provider}} ->
        audit(:cache_hit, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider,
          verdict: :unknown,
          cached: true
        })

        :unknown

      :miss ->
        lookup_with_negative_cache(company_id, sha256, config, now)
    end
  end

  defp lookup_with_negative_cache(company_id, sha256, config, now) do
    provider = Map.get(config, :provider, HttpProvider)
    provider_name = safe_provider_name(provider)

    case check_error_guard(provider_name, sha256, config) do
      {:error, reason} ->
        audit_warning(:error_fail_open, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider_name,
          verdict: :error,
          cached: true,
          reason: inspect(reason)
        })

        {:error, reason}

      :ok ->
        lookup_remote(company_id, sha256, config, now)
    end
  end

  defp lookup_remote(company_id, sha256, config, now) do
    provider = Map.get(config, :provider, HttpProvider)
    provider_name = safe_provider_name(provider)

    case provider.lookup(sha256, config) do
      {:ok, :infected, detail} ->
        store_cache(sha256, "infected", provider_name, detail, now, ttl_sec(config, :infected))

        audit(:lookup, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider_name,
          verdict: :infected,
          cached: false,
          detail: detail
        })

        {:infected, detail}

      {:ok, :unknown, detail} ->
        store_cache(sha256, "unknown", provider_name, detail, now, ttl_sec(config, :unknown))

        audit(:lookup, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider_name,
          verdict: :unknown,
          cached: false,
          detail: detail
        })

        :unknown

      {:error, reason} ->
        store_error_guard(provider_name, sha256, reason, config)

        audit_warning(:error_fail_open, %{
          company_id: company_id,
          sha256: sha256,
          provider: provider_name,
          verdict: :error,
          cached: false,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp check_error_guard(provider_name, sha256, config) do
    error_ttl = Map.get(config, :error_ttl_sec, @default_error_ttl_sec)
    circuit_ttl = Map.get(config, :circuit_open_sec, @default_circuit_open_sec)

    with :ok <- check_negative_cache(provider_name, sha256, error_ttl) do
      check_circuit_breaker(provider_name, circuit_ttl)
    end
  end

  defp check_negative_cache(_provider_name, _sha256, error_ttl) when error_ttl <= 0, do: :ok

  defp check_negative_cache(provider_name, sha256, _error_ttl) do
    case Cache.get({:reputation_error, provider_name, sha256}) do
      {:ok, {:error, _reason} = cached} -> cached
      _other -> :ok
    end
  end

  defp check_circuit_breaker(_provider_name, circuit_ttl) when circuit_ttl <= 0, do: :ok

  defp check_circuit_breaker(provider_name, _circuit_ttl) do
    case Cache.get({:reputation_circuit_open, provider_name}) do
      {:ok, {:open, reason}} -> {:error, {:circuit_open, reason}}
      _other -> :ok
    end
  end

  defp store_error_guard(provider_name, sha256, reason, config) do
    error_ttl = Map.get(config, :error_ttl_sec, @default_error_ttl_sec)
    circuit_ttl = Map.get(config, :circuit_open_sec, @default_circuit_open_sec)

    _error_put =
      if error_ttl > 0 do
        Cache.put(
          {:reputation_error, provider_name, sha256},
          {:error, reason},
          expire: :timer.seconds(error_ttl)
        )
      end

    _circuit_put =
      if circuit_ttl > 0 do
        Cache.put(
          {:reputation_circuit_open, provider_name},
          {:open, reason},
          expire: :timer.seconds(circuit_ttl)
        )
      end

    :ok
  end

  defp fetch_valid_cache(sha256, now) do
    result =
      AttachmentReputationCache
      |> Ash.Query.filter(sha256 == ^sha256)
      |> Ash.read_one(domain: Helpdesk, authorize?: false)

    case result do
      {:ok, %AttachmentReputationCache{expires_at: expires_at} = entry} ->
        if DateTime.compare(expires_at, now) == :gt do
          {:ok, entry}
        else
          :miss
        end

      {:ok, nil} ->
        :miss

      {:error, error} ->
        Logger.warning("attachment_reputation cache_read_failed #{inspect(error)}")
        :miss
    end
  end

  defp store_cache(sha256, verdict, provider, detail, now, ttl_seconds) do
    expires_at = DateTime.add(now, ttl_seconds, :second)

    attrs = %{
      sha256: sha256,
      verdict: verdict,
      provider: provider,
      detail: detail,
      checked_at: now,
      expires_at: expires_at
    }

    case AttachmentReputationCache
         |> Ash.Changeset.for_create(:create, attrs)
         |> Ash.create(domain: Helpdesk, authorize?: false) do
      {:ok, _entry} ->
        :ok

      {:error, error} ->
        Logger.warning("attachment_reputation cache_write_failed #{inspect(error)}")
        :ok
    end
  end

  defp fetch_company(company_id) do
    Company
    |> Ash.Query.filter(id == ^company_id)
    |> Ash.read_one(domain: Accounts, authorize?: false)
  end

  defp current_config do
    :helpdesk_commander
    |> Application.get_env(:attachment_reputation, [])
    |> Map.new()
  end

  defp ttl_sec(config, :infected) do
    Map.get(config, :infected_ttl_sec, @default_infected_ttl_sec)
  end

  defp ttl_sec(config, :unknown) do
    Map.get(config, :unknown_ttl_sec, @default_unknown_ttl_sec)
  end

  defp safe_provider_name(provider) do
    if function_exported?(provider, :name, 0) do
      provider.name()
    else
      inspect(provider)
    end
  end

  defp audit(event, data) do
    Logger.info("attachment_reputation #{event} #{inspect(data)}")
  end

  defp audit_warning(event, data) do
    Logger.warning("attachment_reputation #{event} #{inspect(data)}")
  end
end
