defmodule Wasomi.Repo.Migrations.AddFlashcardSourceAndMasteredStatus do
  use Ecto.Migration

  def up do
    alter table(:flashcard_sets) do
      add :source, :string
    end

    create constraint(:flashcard_sets, :flashcard_sets_source_must_be_valid,
             check: "source IS NULL OR source IN ('practice_questions', 'lesson_text')"
           )

    drop constraint(:flashcard_progress, :flashcard_progress_status_must_be_valid)

    create constraint(:flashcard_progress, :flashcard_progress_status_must_be_valid,
             check: "status IN ('unseen', 'known', 'review_again', 'mastered')"
           )
  end

  def down do
    drop constraint(:flashcard_sets, :flashcard_sets_source_must_be_valid)

    alter table(:flashcard_sets) do
      remove :source
    end

    execute "UPDATE flashcard_progress SET status = 'known' WHERE status = 'mastered'"

    drop constraint(:flashcard_progress, :flashcard_progress_status_must_be_valid)

    create constraint(:flashcard_progress, :flashcard_progress_status_must_be_valid,
             check: "status IN ('unseen', 'known', 'review_again')"
           )
  end
end
