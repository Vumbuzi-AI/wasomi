# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :wasomi,
  ecto_repos: [Wasomi.Repo],
  generators: [timestamp_type: :utc_datetime],
  payment_provider: Wasomi.Paystack,
  media_provider: Wasomi.Media.Mux,
  certificate_storage: Wasomi.Certificates.Storage.R2,
  paystack_api_url: "https://api.paystack.co",
  paystack_callback_url: "http://localhost:4000/payments/paystack/callback",
  mux_api_url: "https://api.mux.com",
  mux_cors_origin: "http://localhost:4000"

config :wasomi, Oban,
  repo: Wasomi.Repo,
  queues: [payments: 10, certificates: 3, mailers: 5, default: 10],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Wasomi.Payments.Workers.ReconcilePendingPayments}
     ]}
  ]

# Configures the endpoint
config :wasomi, WasomiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WasomiWeb.ErrorHTML, json: WasomiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Wasomi.PubSub,
  live_view: [signing_salt: "YpHs4ZS0"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :wasomi, Wasomi.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  wasomi: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  wasomi: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
