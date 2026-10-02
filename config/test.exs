import Config

# Tests never read or create the user's desktop configuration.
config :cards_one,
  sync_catalogue_on_start: false,
  config_file: Path.join(System.tmp_dir!(), "cards_one-test-#{System.pid()}/config.toml")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cards_one, CardsOne.Repo,
  database: Path.expand("../cards_one_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cards_one, CardsOneWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "p+rdaR1ujReGza31zCP3gyPJfas9UIJp4TQ7s6rtvc8uZkZFPqt+hc1ssok2UjnM",
  server: false

# In test we don't send emails
config :cards_one, CardsOne.Mailer, adapter: Swoosh.Adapters.Test

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
