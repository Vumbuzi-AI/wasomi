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
  assessments_storage: Wasomi.AssessmentsStorageMock,
  pdf_extractor: Wasomi.PdfExtractorMock,
  question_generator: Wasomi.QuestionGeneratorMock,
  transcriber: Wasomi.TranscriberMock,
  lecture_question_scorer: Wasomi.LectureQuestionScorerMock,
  lecture_resource_reader: Wasomi.LectureResourceReaderMock,
  docx_extractor: Wasomi.DocxExtractorMock,
  flashcard_generator: Wasomi.FlashcardGeneratorMock,
  r2_public_url: "https://test-storage.example.com",
  req_options: [plug: {Req.Test, Wasomi.Assessments.LectureResourceReader.Storage}],
  catalog_storage: Wasomi.CatalogStorageMock,
  overview_script_generator: Wasomi.OverviewScriptGeneratorMock,
  overview_narrator: Wasomi.OverviewNarratorMock,
  overview_image_generator: Wasomi.OverviewImageGeneratorMock,
  slide_renderer: Wasomi.SlideRendererMock,
  video_assembler: Wasomi.VideoAssemblerMock,
  link_text_fetcher: Wasomi.LinkTextFetcherMock,
  paystack_secret_key: "test_paystack_secret",
  paystack_callback_url: "http://www.example.com/payments/paystack/callback",
  openai_api_key: "test_openai_key",
  openai_scorer_req_options: [
    plug: {Req.Test, Wasomi.Catalog.LectureQuestionScorer.OpenAI},
    retry: false
  ]

config :wasomi, Oban, testing: :manual, queues: false, plugins: false

# ChromicPDF needs a headless Chrome/Chromium binary; the real
# certificate_renderer is never configured in test, so skip the supervision
# tree entry to keep CI from requiring a browser.
config :wasomi, :start_chromic_pdf, false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
