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
#     PHX_SERVER=true bin/wasomi start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :wasomi, WasomiWeb.Endpoint, server: true
end

if paystack_secret_key = System.get_env("PAYSTACK_SECRET_KEY") do
  config :wasomi, paystack_secret_key: paystack_secret_key
end

if paystack_api_url = System.get_env("PAYSTACK_API_URL") do
  config :wasomi, paystack_api_url: paystack_api_url
end

if paystack_callback_url = System.get_env("PAYSTACK_CALLBACK_URL") do
  config :wasomi, paystack_callback_url: paystack_callback_url
end

for {env_name, config_key} <- [
      {"MUX_TOKEN_ID", :mux_token_id},
      {"MUX_TOKEN_SECRET", :mux_token_secret},
      {"MUX_SIGNING_KEY_ID", :mux_signing_key_id},
      {"MUX_SIGNING_PRIVATE_KEY", :mux_signing_private_key},
      {"MUX_API_URL", :mux_api_url},
      {"MUX_CORS_ORIGIN", :mux_cors_origin}
    ],
    value = System.get_env(env_name),
    value not in [nil, ""] do
  config :wasomi, config_key, value
end

for {env_name, config_key} <- [
      {"R2_BUCKET", :r2_bucket},
      {"R2_ACCESS_KEY_ID", :r2_access_key_id},
      {"R2_SECRET_ACCESS_KEY", :r2_secret_access_key}
    ],
    value = System.get_env(env_name),
    value not in [nil, ""] do
  config :wasomi, config_key, value
end

if r2_endpoint = System.get_env("R2_ENDPOINT") do
  uri = URI.parse(r2_endpoint)

  config :ex_aws,
    access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
    region: "auto"

  config :ex_aws, :s3,
    scheme: "#{uri.scheme || "https"}://",
    host: uri.host,
    port: uri.port,
    region: "auto"
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :wasomi, Wasomi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
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
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :wasomi, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :wasomi, WasomiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :wasomi,
    paystack_secret_key:
      "sk_test_7267bf7b9b38cd9798c6328f7e0b3cc5a264f4aa" ||
        raise("environment variable PAYSTACK_SECRET_KEY is missing"),
    paystack_callback_url:
      System.get_env("PAYSTACK_CALLBACK_URL") ||
        "https://#{host}/payments/paystack/callback",
    mux_token_id:
      System.get_env("MUX_TOKEN_ID") ||
        raise("environment variable MUX_TOKEN_ID is missing"),
    mux_token_secret:
      System.get_env("MUX_TOKEN_SECRET") ||
        raise("environment variable MUX_TOKEN_SECRET is missing"),
    mux_signing_key_id:
      System.get_env("MUX_SIGNING_KEY_ID") ||
        raise("environment variable MUX_SIGNING_KEY_ID is missing"),
    mux_signing_private_key:
      System.get_env("MUX_SIGNING_PRIVATE_KEY") ||
        raise("environment variable MUX_SIGNING_PRIVATE_KEY is missing"),
    mux_cors_origin: System.get_env("MUX_CORS_ORIGIN") || "https://#{host}",
    r2_bucket:
      System.get_env("R2_BUCKET") ||
        raise("environment variable R2_BUCKET is missing"),
    r2_access_key_id:
      System.get_env("R2_ACCESS_KEY_ID") ||
        raise("environment variable R2_ACCESS_KEY_ID is missing"),
    r2_secret_access_key:
      System.get_env("R2_SECRET_ACCESS_KEY") ||
        raise("environment variable R2_SECRET_ACCESS_KEY is missing")

  if is_nil(System.get_env("R2_ENDPOINT")) do
    raise "environment variable R2_ENDPOINT is missing"
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :wasomi, WasomiWeb.Endpoint,
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
  #     config :wasomi, WasomiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :wasomi, Wasomi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
