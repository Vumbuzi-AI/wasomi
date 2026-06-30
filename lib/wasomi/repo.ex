defmodule Wasomi.Repo do
  use Ecto.Repo,
    otp_app: :wasomi,
    adapter: Ecto.Adapters.Postgres
end
