defmodule Wasomi.Repo.Migrations.CreateStudyGuides do
  use Ecto.Migration

  def change do
    # Same per-user shape as smart_tests rather than the one-shared-set-per-scope
    # shape of flashcard_sets/practice_sets: a study guide is written to the
    # learner's own brief (style, depth, reading level, and their own free-text
    # focus), so two learners on the same module want two different documents,
    # and asking for another style is a new guide rather than an overwrite.
    create table(:study_guides) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :module_id, references(:modules, on_delete: :delete_all)
      add :lecture_id, references(:lectures, on_delete: :delete_all)

      add :style, :string, null: false
      add :depth, :string, null: false
      add :reading_level, :string, null: false
      add :include_key_terms, :boolean, null: false, default: true
      add :include_examples, :boolean, null: false, default: true
      add :focus, :text

      add :title, :text
      add :summary, :text
      add :key_takeaways, {:array, :text}, null: false, default: []
      add :key_terms, {:array, :map}, null: false, default: []

      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :sections_generated_count, :integer
      add :generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:study_guides, [:user_id, :module_id])
    create index(:study_guides, [:user_id, :lecture_id])

    create constraint(:study_guides, :study_guides_scope_must_be_exclusive,
             check: "(module_id IS NOT NULL) <> (lecture_id IS NOT NULL)"
           )

    create constraint(:study_guides, :study_guides_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    create constraint(:study_guides, :study_guides_style_must_be_valid,
             check: "style IN ('story', 'notes', 'cheat_sheet', 'q_and_a', 'analogies')"
           )

    create constraint(:study_guides, :study_guides_depth_must_be_valid,
             check: "depth IN ('brief', 'standard', 'deep')"
           )

    create constraint(:study_guides, :study_guides_reading_level_must_be_valid,
             check: "reading_level IN ('beginner', 'intermediate', 'advanced')"
           )

    # Sections are rows rather than one blob of model-authored HTML on purpose:
    # the document is rendered from structured fields by our own templates, so
    # nothing the model returns is ever trusted as markup.
    create table(:study_guide_sections) do
      add :study_guide_id, references(:study_guides, on_delete: :delete_all), null: false
      add :heading, :text, null: false
      add :body, :text
      add :bullets, {:array, :text}, null: false, default: []
      add :callout, :text
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:study_guide_sections, [:study_guide_id, :position])

    create constraint(:study_guide_sections, :study_guide_sections_position_must_be_positive,
             check: "position > 0"
           )
  end
end
