import Config
config :ash, disable_async?: true

config :helpdesk_commander, :company_code_hmac_secret, "test-company-code-secret"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# Prefer TEST_DATABASE_URL when provided, but keep partition support by rewriting
# the database name in the URL's path.
#
# Example:
#   export TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/helpdesk_commander_test

test_database_url = System.get_env("TEST_DATABASE_URL")

test_database_base = System.get_env("TEST_DATABASE_NAME", "helpdesk_commander_test")
test_database = test_database_base <> to_string(System.get_env("MIX_TEST_PARTITION", ""))

repo_base =
  if test_database_url do
    uri = URI.parse(test_database_url)
    uri = %{uri | path: "/" <> test_database}

    [url: URI.to_string(uri)]
  else
    username = System.get_env("POSTGRES_USER", "postgres")
    password = System.get_env("POSTGRES_PASSWORD", "postgres")
    hostname = System.get_env("POSTGRES_HOST", "localhost")
    port = String.to_integer(System.get_env("POSTGRES_PORT", "5432"))

    [
      username: username,
      password: password,
      hostname: hostname,
      port: port,
      database: test_database
    ]
  end

config :helpdesk_commander,
       HelpdeskCommander.Repo,
       repo_base ++
         [
           pool: Ecto.Adapters.SQL.Sandbox,
           pool_size: System.schedulers_online() * 2
         ]

config :helpdesk_commander, Oban, testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :helpdesk_commander, HelpdeskCommanderWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "03ul96NAvSXF4mWME8SX9d4KvFKKqoqUVs63DgB6loz9wXuH6o7Ab76NKrUrJsWN",
  server: false

# In test we don't send emails
config :helpdesk_commander, HelpdeskCommander.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
