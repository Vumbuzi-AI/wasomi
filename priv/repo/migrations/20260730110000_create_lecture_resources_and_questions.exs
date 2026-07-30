defmodule Wasomi.Repo.Migrations.CreateLectureResourcesAndQuestions do
  use Ecto.Migration

  def change do
    create table(:lecture_resources) do
      add :kind, :string, null: false
      add :name, :string, null: false
      add :storage_key, :string
      add :url, :text
      add :content_type, :string
      add :byte_size, :bigint
      add :position, :integer, null: false
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_resources, [:lecture_id])
    create unique_index(:lecture_resources, [:lecture_id, :position])

    create constraint(:lecture_resources, :lecture_resources_kind_must_be_valid,
             check: "kind IN ('document', 'video', 'link')"
           )

    create constraint(:lecture_resources, :lecture_resources_position_must_be_positive,
             check: "position > 0"
           )

    create constraint(:lecture_resources, :lecture_resources_byte_size_must_be_positive,
             check: "byte_size IS NULL OR byte_size > 0"
           )

    create table(:lecture_questions) do
      add :question, :text, null: false
      add :answer, :text, null: false
      add :position, :integer, null: false
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_questions, [:lecture_id])
    create unique_index(:lecture_questions, [:lecture_id, :position])

    create constraint(:lecture_questions, :lecture_questions_position_must_be_positive,
             check: "position > 0"
           )
  end
end
