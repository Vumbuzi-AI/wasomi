defmodule Wasomi.Repo.Migrations.AddAnalyticsIndexes do
  use Ecto.Migration

  def change do
    create index(:payments, [:paid_at], where: "status = 'successful'")
    create index(:lecture_progress, [:lecture_id, :status])
    create index(:quiz_submissions, [:quiz_id, :submitted_at])
  end
end
