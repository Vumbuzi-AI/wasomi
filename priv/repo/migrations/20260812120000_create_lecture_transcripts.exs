defmodule Wasomi.Repo.Migrations.CreateLectureTranscripts do
  use Ecto.Migration

  def change do
    create table(:lecture_transcripts) do
      add :status, :string, null: false, default: "pending"
      add :text, :text
      add :error, :string
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lecture_transcripts, [:lecture_id])

    create constraint(:lecture_transcripts, :lecture_transcripts_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )
  end
end
