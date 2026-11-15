defmodule HelpdeskCommander.Attachments.ReputationTest do
  use HelpdeskCommander.DataCase, async: false

  import ExUnit.CaptureLog

  alias HelpdeskCommander.Accounts
  alias HelpdeskCommander.Accounts.Company
  alias HelpdeskCommander.Attachments.Reputation
  alias HelpdeskCommander.Attachments.Reputation.HttpProvider
  alias HelpdeskCommander.Helpdesk
  alias HelpdeskCommander.Helpdesk.AttachmentReputationCache

  @sample_sha256 String.duplicate("a", 64)

  defmodule FakeProvider do
    @behaviour HelpdeskCommander.Attachments.Reputation.Provider

    @impl true
    def name, do: "fake"

    @impl true
    def lookup(sha256, config) do
      if pid = Map.get(config, :test_pid) do
        send(pid, {:lookup_called, sha256})
      end

      case Map.get(config, :verdict, :unknown) do
        {:infected, detail} -> {:ok, :infected, detail}
        :unknown -> {:ok, :unknown, nil}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :info)
    Cachex.clear(HelpdeskCommander.Cache)
    company = create_company!()

    on_exit(fn ->
      Logger.configure(level: previous_level)
      Application.delete_env(:helpdesk_commander, :attachment_reputation)
      Cachex.clear(HelpdeskCommander.Cache)
    end)

    %{company: company}
  end

  describe "HttpProvider" do
    test "returns :infected on 200 and sends only sha256 via URL placeholder" do
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:http_request, conn.method, conn.request_path, conn.query_string})
        Req.Test.json(conn, %{"verdict" => "malicious", "family" => "EICAR-Test"})
      end

      config = %{
        url: "https://feed.example.test/v1/hashes/{sha256}",
        verdict_path: ["verdict"],
        detail_path: ["family"],
        req_options: [plug: plug]
      }

      assert {:ok, :infected, "EICAR-Test"} = HttpProvider.lookup(@sample_sha256, config)

      assert_receive {:http_request, "GET", path, ""}
      assert path == "/v1/hashes/#{@sample_sha256}"
    end

    test "returns :unknown on 404" do
      plug = fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end

      config = %{
        url: "https://feed.example.test/v1/hashes/{sha256}",
        req_options: [plug: plug]
      }

      assert {:ok, :unknown, nil} = HttpProvider.lookup(@sample_sha256, config)
    end

    test "sends only sha256 JSON payload in POST mode and evaluates integer count" do
      test_pid = self()

      plug = fn conn ->
        {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:post_body, Jason.decode!(raw_body)})
        Req.Test.json(conn, %{"data" => %{"malicious" => 0}})
      end

      config = %{
        url: "https://feed.example.test/v1/lookup",
        method: :post,
        verdict_path: ["data", "malicious"],
        req_options: [plug: plug]
      }

      assert {:ok, :unknown, nil} = HttpProvider.lookup(@sample_sha256, config)
      assert_receive {:post_body, %{"sha256" => @sample_sha256}}
    end

    test "returns error on 5xx, timeout, or missing url" do
      plug_500 = fn conn -> Plug.Conn.send_resp(conn, 500, "err") end

      assert {:error, {:http_status, 500}} =
               HttpProvider.lookup(@sample_sha256, %{
                 url: "https://feed.example.test/{sha256}",
                 req_options: [plug: plug_500]
               })

      plug_timeout = fn conn -> Req.Test.transport_error(conn, :timeout) end

      assert {:error, {:request_failed, _reason}} =
               HttpProvider.lookup(@sample_sha256, %{
                 url: "https://feed.example.test/{sha256}",
                 req_options: [plug: plug_timeout]
               })

      assert {:error, :reputation_url_not_configured} = HttpProvider.lookup(@sample_sha256, %{})
      assert {:error, :invalid_sha256} = HttpProvider.lookup("not-a-hash", %{url: "https://x.test"})
    end
  end

  describe "Reputation.check/2" do
    test "defaults to disabled and never calls provider", %{company: company} do
      Application.put_env(:helpdesk_commander, :attachment_reputation,
        enabled: false,
        provider: FakeProvider,
        test_pid: self()
      )

      assert :disabled = Reputation.check(company.id, @sample_sha256)
      refute_receive {:lookup_called, _}
    end

    test "does not query provider when company setting is disabled even if global enabled", %{
      company: company
    } do
      Application.put_env(:helpdesk_commander, :attachment_reputation,
        enabled: true,
        provider: FakeProvider,
        test_pid: self()
      )

      refute Reputation.company_enabled?(company.id)
      assert :disabled = Reputation.check(company.id, @sample_sha256)
      refute_receive {:lookup_called, _}
    end

    test "caches verdict and suppresses duplicate remote lookups with audit logs", %{
      company: company
    } do
      {:ok, _updated} = Reputation.set_company_enabled(company.id, true)

      Application.put_env(:helpdesk_commander, :attachment_reputation,
        enabled: true,
        provider: FakeProvider,
        verdict: {:infected, "Trojan.Test"},
        test_pid: self()
      )

      log1 =
        capture_log([level: :info], fn ->
          assert {:infected, "Trojan.Test"} = Reputation.check(company.id, @sample_sha256)
        end)

      assert_receive {:lookup_called, @sample_sha256}
      assert log1 =~ "attachment_reputation lookup"
      assert log1 =~ "cached: false"

      log2 =
        capture_log([level: :info], fn ->
          assert {:infected, "Trojan.Test"} = Reputation.check(company.id, @sample_sha256)
        end)

      refute_receive {:lookup_called, _}
      assert log2 =~ "attachment_reputation cache_hit"
      assert log2 =~ "cached: true"
    end

    test "re-queries provider when cache entry is expired", %{company: company} do
      {:ok, _updated} = Reputation.set_company_enabled(company.id, true)

      past = DateTime.add(DateTime.utc_now(), -120, :second)

      {:ok, _entry} =
        AttachmentReputationCache
        |> Ash.Changeset.for_create(:create, %{
          sha256: @sample_sha256,
          verdict: "unknown",
          provider: "fake",
          checked_at: past,
          expires_at: DateTime.add(past, 60, :second)
        })
        |> Ash.create(domain: Helpdesk, authorize?: false)

      Application.put_env(:helpdesk_commander, :attachment_reputation,
        enabled: true,
        provider: FakeProvider,
        verdict: :unknown,
        test_pid: self()
      )

      assert :unknown = Reputation.check(company.id, @sample_sha256)
      assert_receive {:lookup_called, @sample_sha256}
    end

    test "negative-caches errors and opens circuit breaker to prevent stall", %{company: company} do
      {:ok, _updated} = Reputation.set_company_enabled(company.id, true)

      Application.put_env(:helpdesk_commander, :attachment_reputation,
        enabled: true,
        provider: FakeProvider,
        verdict: {:error, :timeout},
        error_ttl_sec: 60,
        circuit_open_sec: 30,
        test_pid: self()
      )

      log =
        capture_log(fn ->
          assert {:error, :timeout} = Reputation.check(company.id, @sample_sha256)
        end)

      assert log =~ "attachment_reputation error_fail_open"
      assert_receive {:lookup_called, @sample_sha256}

      # 2 回目はネガティブキャッシュにより外部照会せず即座に fail-open
      assert {:error, :timeout} = Reputation.check(company.id, @sample_sha256)
      refute_receive {:lookup_called, _}

      # 別ハッシュでもサーキットブレーカーにより外部照会しない
      other_sha256 = String.duplicate("b", 64)
      assert {:error, {:circuit_open, :timeout}} = Reputation.check(company.id, other_sha256)
      refute_receive {:lookup_called, _}

      # Cachex 4 に有効な TTL（:expire）が設定されていることを検証
      assert {:ok, error_ttl_ms} =
               Cachex.ttl(HelpdeskCommander.Cache, {:reputation_error, "fake", @sample_sha256})

      assert is_integer(error_ttl_ms) and error_ttl_ms > 0 and error_ttl_ms <= 60_000

      assert {:ok, circuit_ttl_ms} =
               Cachex.ttl(HelpdeskCommander.Cache, {:reputation_circuit_open, "fake"})

      assert is_integer(circuit_ttl_ms) and circuit_ttl_ms > 0 and circuit_ttl_ms <= 30_000
    end
  end

  defp create_company! do
    suffix = System.unique_integer([:positive]) |> Integer.to_string() |> String.slice(-6, 6)

    Company
    |> Ash.Changeset.for_create(:create, %{
      name: "Rep Corp #{System.unique_integer([:positive])}",
      company_code: "A-#{String.pad_leading(suffix, 6, "0")}"
    })
    |> Ash.create!(domain: Accounts, authorize?: false)
  end
end
