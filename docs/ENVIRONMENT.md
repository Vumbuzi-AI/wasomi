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
| `CLOUDFLARE_ACCOUNT_ID` | yes | Cloudflare account identifier. |
| `CLOUDFLARE_STREAM_API_TOKEN` | yes | API token with Stream read/write access. |
| `CLOUDFLARE_STREAM_CUSTOMER_CODE` | yes | Customer subdomain code or full `customer-….cloudflarestream.com` hostname used for Stream delivery. |
| `CLOUDFLARE_STREAM_SIGNING_KEY_ID` | yes | Stream signing-key identifier. |
| `CLOUDFLARE_STREAM_SIGNING_PRIVATE_KEY` | yes | Base64-encoded PEM returned with the signing key. |
| `CLOUDFLARE_API_URL` | optional | Overrides the Cloudflare API base URL. |
| `CLOUDFLARE_STREAM_ORIGIN` | optional | Allowed playback origin; prod defaults to `https://#{PHX_HOST}`. |
| `R2_BUCKET` | yes | Lecture resource bucket. |
| `R2_ACCESS_KEY_ID` | yes | R2/S3 access key. |
| `R2_SECRET_ACCESS_KEY` | yes | R2/S3 secret key. |
| `R2_ENDPOINT` | yes | R2/S3-compatible endpoint and ExAws S3 host. |
| `R2_PUBLIC_URL` | yes | Public base URL used to access uploaded lecture resources. |
| `R2_UPLOAD_EXPIRY` | optional | Presigned upload URL lifetime in seconds; defaults to `900`. |
| `CHROME_EXECUTABLE` | optional | Path to a Chrome/Chromium binary for `ChromicPDF` (certificate PDF rendering). ChromicPDF auto-detects common install paths/names; set this when the binary lives somewhere nonstandard (e.g. local dev machines). |
| `CHROME_NO_SANDBOX` | optional | Set to `1`/`true` to start Chrome with `--no-sandbox`. Sandboxed by default; only needed when the deployment target can't grant Chrome's sandbox the privileges it needs (commonly: running as root in a container). |

`config/config.exs` also sets defaults for `payment_provider`, `media_provider`, `certificate_renderer`, `certificate_storage`, Paystack API URL, callback URL, Cloudflare API URL, and Stream origin.

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
