import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :wasomi, Wasomi.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "wasomi_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :wasomi, WasomiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sWzOPYRXNg32B8Y7jgDbRCOW05wKm4Lvk/4aYe8Bem3f0OGIb20D/R1OtTzvKfRG",
  server: false

# In test we don't send emails
config :wasomi, Wasomi.Mailer, adapter: Swoosh.Adapters.Test

config :wasomi,
  payment_provider: Wasomi.Payments.ProviderMock,
  media_provider: Wasomi.MediaProviderMock,
  certificate_renderer: Wasomi.CertificateRendererMock,
  certificate_storage: Wasomi.CertificateStorageMock,
  paystack_secret_key: "test_paystack_secret",
  paystack_callback_url: "http://www.example.com/payments/paystack/callback"

config :wasomi, Oban, testing: :manual, queues: false, plugins: false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
