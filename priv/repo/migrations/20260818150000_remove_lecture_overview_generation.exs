defmodule Wasomi.Repo.Migrations.RemoveLectureOverviewGeneration do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM oban_jobs
    WHERE worker IN (
      'Wasomi.Catalog.Workers.GenerateLectureOverviewWorker',
      'Wasomi.Catalog.Workers.AttachLectureOverviewVideoWorker'
    )
    """)

    drop table(:lecture_overview_generations)
  end

  def down do
    create table(:lecture_overview_generations) do
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :scene_count, :integer
      add :video_storage_key, :string
      add :attach_status, :string, null: false, default: "not_attached"
      add :attach_asset_id, :string
      add :attach_error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_overview_generations, [:lecture_id])
  end
end
