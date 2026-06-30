# Environment

## Development

`config/dev.exs` sets local defaults:

| Setting | Value |
| --- | --- |
| Database | `wasomi_dev` |
| DB username | `postgres` |
| DB password | `postgres` |
| DB host | `localhost` |
| HTTP port | `4590` |
| Media provider | `Wasomi.Media.Demo` |
| Dev routes | enabled |

Development uses local Swoosh mail storage and watches esbuild/Tailwind assets.

## Test

`config/test.exs` uses:

- `wasomi_test#{MIX_TEST_PARTITION}` database
- Ecto SQL sandbox
- `Wasomi.Payments.ProviderMock`
- `Wasomi.MediaProviderMock`
- `Wasomi.CertificateRendererMock`
- `Wasomi.CertificateStorageMock`
- Oban testing mode with queues/plugins disabled

## Runtime and Production Variables

| Variable | Required in prod | Purpose |
| --- | --- | --- |
| `PHX_SERVER` | optional | Starts the endpoint in releases when set. |
| `DATABASE_URL` | yes | Production database URL. |
| `SECRET_KEY_BASE` | yes | Cookie/session signing secret. |
| `PHX_HOST` | optional | Public host, default `example.com`. |
| `PORT` | optional | HTTP port, default `4000`. |
| `POOL_SIZE` | optional | Repo pool size, default `10`. |
| `ECTO_IPV6` | optional | Enables IPv6 socket options when `true` or `1`. |
| `DNS_CLUSTER_QUERY` | optional | DNS clustering query. |
| `PAYSTACK_SECRET_KEY` | intended required | Paystack API secret. TODO: runtime config currently contains a hard-coded fallback expression that prevents the prod raise from triggering. Replace it with `System.get_env("PAYSTACK_SECRET_KEY") || raise(...)`. |
| `PAYSTACK_API_URL` | optional | Overrides Paystack API base URL. |
| `PAYSTACK_CALLBACK_URL` | optional | Overrides callback URL; prod defaults to `https://#{PHX_HOST}/payments/paystack/callback`. |
| `MUX_TOKEN_ID` | yes | Mux API token id. |
| `MUX_TOKEN_SECRET` | yes | Mux API token secret. |
| `MUX_SIGNING_KEY_ID` | yes | Mux playback signing key id. |
| `MUX_SIGNING_PRIVATE_KEY` | yes | Mux playback signing private key. |
| `MUX_API_URL` | optional | Overrides Mux API base URL. |
| `MUX_CORS_ORIGIN` | optional | Playback/upload CORS origin; prod defaults to `https://#{PHX_HOST}`. |
| `R2_BUCKET` | yes | Certificate PDF bucket. |
| `R2_ACCESS_KEY_ID` | yes | R2/S3 access key. |
| `R2_SECRET_ACCESS_KEY` | yes | R2/S3 secret key. |
| `R2_ENDPOINT` | yes | R2/S3-compatible endpoint and ExAws S3 host. |

`config/config.exs` also sets defaults for `payment_provider`, `media_provider`, `certificate_storage`, Paystack API URL, callback URL, Mux API URL, and Mux CORS origin.

## Assets

The app uses Phoenix's esbuild and Tailwind asset pipeline:

- `mix assets.setup`
- `mix assets.build`
- `mix assets.deploy`

## Aliases and Destructive Commands

`mix setup` runs dependency install, database setup, seeds, asset install, and asset build.

`mix ecto.setup` runs create, migrate, and seeds.

`mix ecto.reset` drops the database before recreating, migrating, and seeding. Use it only when local data can be discarded.

No alias is intentionally blocked or overridden in `mix.exs`.
