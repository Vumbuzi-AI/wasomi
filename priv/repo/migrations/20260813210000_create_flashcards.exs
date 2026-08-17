defmodule Wasomi.Repo.Migrations.CreateFlashcards do
  use Ecto.Migration

  def change do
    create table(:flashcard_sets) do
      add :module_id, references(:modules, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :cards_generated_count, :integer
      add :generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flashcard_sets, [:module_id])

    create constraint(:flashcard_sets, :flashcard_sets_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    create table(:flashcards) do
      add :flashcard_set_id, references(:flashcard_sets, on_delete: :delete_all), null: false
      add :front, :text, null: false
      add :back, :text, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flashcards, [:flashcard_set_id, :position])

    create constraint(:flashcards, :flashcards_position_must_be_positive, check: "position > 0")

    create table(:flashcard_progress) do
      add :flashcard_id, references(:flashcards, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "unseen"
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:flashcard_progress, [:flashcard_id, :user_id])

    create constraint(:flashcard_progress, :flashcard_progress_status_must_be_valid,
             check: "status IN ('unseen', 'known', 'review_again')"
           )
  end
end
