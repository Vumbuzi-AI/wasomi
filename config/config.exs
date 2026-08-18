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
  media_provider: Wasomi.Media.Cloudflare,
  storage_provider: Wasomi.Storage.R2,
  certificate_renderer: Wasomi.Certificates.Renderer.ChromicPdf,
  chromic_pdf_options: [
    session_pool: [
      size: 2,
      init_timeout: 30_000,
      timeout: 30_000,
      checkout_timeout: 30_000
    ]
  ],
  certificate_storage: Wasomi.Certificates.Storage.R2,
  assessments_storage: Wasomi.Assessments.Storage.R2,
  pdf_extractor: Wasomi.Assessments.PdfExtractor.PdfToText,
  question_generator: Wasomi.Assessments.QuestionGenerator.OpenAI,
  transcriber: Wasomi.Catalog.Transcriber.OpenAI,
  lecture_question_scorer: Wasomi.Catalog.LectureQuestionScorer.OpenAI,
  lecture_resource_reader: Wasomi.Assessments.LectureResourceReader.Storage,
  paystack_api_url: "https://api.paystack.co",
  paystack_callback_url: "http://localhost:4000/payments/paystack/callback",
  cloudflare_api_url: "https://api.cloudflare.com",
  cloudflare_stream_origin: "http://localhost:4000"

# ExAws defaults to :hackney; reuse the app's Finch pool instead so hackney
# (and its `quic` dependency) stays out of the dependency tree.
config :ex_aws, http_client: Wasomi.ExAws.HttpClient

config :wasomi, Oban,
  repo: Wasomi.Repo,
  queues: [
    payments: 10,
    certificates: 3,
    mailers: 5,
    quiz_generation: 2,
    transcription: 2,
    default: 10
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Wasomi.Payments.Workers.ReconcilePendingPayments}
     ]},
    # Without this, a job that's stuck `executing` (most commonly: the
    # dev/prod node restarted mid-job, orphaning its DB row with no
    # process actually running it) sits that way forever — no error, no
    # retry, nothing for an admin to see or act on. Lifeline periodically
    # rescues those back to `available` after they've run implausibly
    # long, discarding them instead if they've already exhausted their
    # attempts.
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(15)}
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
