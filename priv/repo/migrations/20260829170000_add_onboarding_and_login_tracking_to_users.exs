defmodule Wasomi.Repo.Migrations.AddOnboardingAndLoginTrackingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_signed_in_at, :utc_datetime
      add :onboarding_completed_at, :utc_datetime
    end

    # Existing accounts predate the first-run flow — treat them as already
    # onboarded so they are never routed into it.
    execute(
      "UPDATE users SET onboarding_completed_at = inserted_at WHERE onboarding_completed_at IS NULL",
      ""
    )
  end
end
