import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/helpdesk_commander start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint, server: true
end

config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :helpdesk_commander, HelpdeskCommander.Chat.Slack,
  bot_token: System.get_env("SLACK_BOT_TOKEN"),
  signing_secret: System.get_env("SLACK_SIGNING_SECRET"),
  channel_id: System.get_env("SLACK_CHAT_CHANNEL_ID"),
  api_base: System.get_env("SLACK_API_BASE") || "https://slack.com/api"

config :helpdesk_commander, :sso,
  enabled: System.get_env("SSO_ENABLED") in ["1", "true", "TRUE", "yes", "YES"],
  base_url: System.get_env("SSO_ISSUER_URL"),
  client_id: System.get_env("SSO_CLIENT_ID"),
  client_secret: System.get_env("SSO_CLIENT_SECRET"),
  redirect_uri: System.get_env("SSO_REDIRECT_URI"),
  company_code: System.get_env("SSO_COMPANY_CODE"),
  auto_provision: System.get_env("SSO_AUTO_PROVISION") || "pending",
  role_claim: System.get_env("SSO_ROLE_CLAIM"),
  admin_group: System.get_env("SSO_ADMIN_GROUP"),
  display_name_claim: System.get_env("SSO_DISPLAY_NAME_CLAIM")

config :helpdesk_commander, HelpdeskCommander.Monitoring.Alerts,
  token: System.get_env("MONITORING_WEBHOOK_TOKEN"),
  company_code: System.get_env("MONITORING_COMPANY_CODE") || "A-000001",
  product_id: System.get_env("MONITORING_PRODUCT_ID")

# clamd サイドカー設定（HC-21）。全環境で読み、設定するとコマンド実行より優先して INSTREAM で検査する。
if clamd_host = System.get_env("ATTACHMENT_SCAN_CLAMD_HOST") do
  config :helpdesk_commander,
         :attachment_scan_clamd,
         host: clamd_host,
         port: String.to_integer(System.get_env("ATTACHMENT_SCAN_CLAMD_PORT") || "3310")
end

if config_env() == :prod do
  remote_ip_enabled =
    System.get_env("REMOTE_IP_ENABLED") in ["1", "true", "TRUE", "yes", "YES"]

  if remote_ip_enabled do
    config :helpdesk_commander, :remote_ip,
      enabled?: true,
      opts: [headers: ["x-forwarded-for", "x-real-ip"]]
  end

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  company_code_secret =
    System.get_env("COMPANY_CODE_HMAC_SECRET") ||
      raise """
      environment variable COMPANY_CODE_HMAC_SECRET is missing.
      """

  config :helpdesk_commander, :company_code_hmac_secret, company_code_secret

  pii_hmac_secret =
    System.get_env("PII_HMAC_SECRET") ||
      raise """
      environment variable PII_HMAC_SECRET is missing.
      """

  config :helpdesk_commander, :pii_hmac_secret, pii_hmac_secret

  config :helpdesk_commander,
         :notification_cooldown_seconds,
         String.to_integer(System.get_env("NOTIFICATION_COOLDOWN_SECONDS") || "300")

  slack_webhook_url = System.get_env("SLACK_WEBHOOK_URL")

  config :helpdesk_commander, HelpdeskCommander.Notifications.External,
    email_enabled: System.get_env("NOTIFICATION_EMAIL_ENABLED") in ["true", "1"],
    chat_enabled: is_binary(slack_webhook_url) and slack_webhook_url != "",
    chat_webhook_url: slack_webhook_url,
    from_email: System.get_env("NOTIFICATION_FROM_EMAIL") || "noreply@helpdesk.local"

  if attachment_root = System.get_env("ATTACHMENTS_ROOT") do
    config :helpdesk_commander, :attachment_root, Path.expand(attachment_root)
  end

  # 本番では添付スキャナの設定を必須にする（fail-closed）。未設定のまま起動させない。
  if config_env() == :prod do
    System.get_env("ATTACHMENT_SCAN_COMMAND") ||
      System.get_env("ATTACHMENT_SCAN_CLAMD_HOST") ||
      raise """
      environment variable ATTACHMENT_SCAN_COMMAND or ATTACHMENT_SCAN_CLAMD_HOST is missing.
      Attachments must be virus-scanned before they can be published. Prefer the
      clamd sidecar (sandboxed, no Docker socket on the app side):

          ATTACHMENT_SCAN_CLAMD_HOST=clamd

      or run a scanner command directly:

          ATTACHMENT_SCAN_COMMAND=clamscan

      The scan runs with a 30 second timeout (ATTACHMENT_SCAN_TIMEOUT_MS) and
      files are quarantined when the scanner fails or times out.
      """
  end

  if scan_command = System.get_env("ATTACHMENT_SCAN_COMMAND") do
    # clamscan が指定されたときだけ、深掘り検査設定（HC-23）を明示的に付ける。
    config :helpdesk_commander,
           :attachment_scan_command,
           HelpdeskCommander.Attachments.Clamav.scan_command(scan_command)
  end

  config :helpdesk_commander,
         :attachment_scan_timeout_ms,
         String.to_integer(System.get_env("ATTACHMENT_SCAN_TIMEOUT_MS") || "30000")

  # シグネチャ更新と鮮度監視（HC-22）。本番は freshclam を既定にし、開発・テストは無効。
  # clamd + db-updater 構成では ATTACHMENT_SIGNATURE_UPDATE_COMMAND="" で無効化し、
  # ワーカーの RELOAD に任せる（docs/SANDBOX_SCANNER.md）。
  signature_update_command =
    case System.get_env("ATTACHMENT_SIGNATURE_UPDATE_COMMAND") do
      nil -> if(config_env() == :prod, do: "freshclam")
      "" -> nil
      command -> command
    end

  config :helpdesk_commander, :attachment_signature_update_command, signature_update_command

  config :helpdesk_commander,
         :attachment_signature_max_age_hours,
         String.to_integer(System.get_env("ATTACHMENT_SIGNATURE_MAX_AGE_HOURS") || "24")

  config :helpdesk_commander,
         :attachment_signature_enforce,
         System.get_env("ATTACHMENT_SIGNATURE_ENFORCE") in ["1", "true", "TRUE", "yes", "YES"]

  config :helpdesk_commander,
         :attachment_rescan_limit,
         String.to_integer(System.get_env("ATTACHMENT_RESCAN_LIMIT") || "500")

  # 組織固有の YARA 検査（HC-25）。未設定なら無効。
  config :helpdesk_commander,
         :attachment_yara_command,
         System.get_env("ATTACHMENT_YARA_COMMAND")

  if yara_rules = System.get_env("ATTACHMENT_YARA_RULES") do
    config :helpdesk_commander, :attachment_yara_rules, yara_rules
  end

  cloak_key =
    System.get_env("CLOAK_KEY") ||
      raise """
      environment variable CLOAK_KEY is missing.
      It must be a Base64 encoded 32 byte key.
      """

  config :helpdesk_commander, HelpdeskCommander.Vault,
    ciphers: [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(cloak_key)}
    ]

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :helpdesk_commander, HelpdeskCommander.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :helpdesk_commander, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :helpdesk_commander, HelpdeskCommander.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
