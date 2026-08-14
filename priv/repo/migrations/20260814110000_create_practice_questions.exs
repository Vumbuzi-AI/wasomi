defmodule Wasomi.Repo.Migrations.CreatePracticeQuestions do
  use Ecto.Migration

  def change do
    create table(:practice_questions) do
      add :prompt, :text, null: false
      add :explanation, :text
      add :position, :integer, null: false
      add :status, :string, null: false, default: "draft"
      add :module_id, references(:modules, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:practice_questions, [:module_id])
    create unique_index(:practice_questions, [:module_id, :position])

    create constraint(:practice_questions, :practice_questions_position_must_be_positive,
             check: "position > 0"
           )

    create constraint(:practice_questions, :practice_questions_status_must_be_valid,
             check: "status IN ('draft', 'published')"
           )

    create table(:practice_question_options) do
      add :label, :text, null: false
      add :correct, :boolean, null: false, default: false
      add :position, :integer, null: false

      add :practice_question_id, references(:practice_questions, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:practice_question_options, [:practice_question_id])
    create unique_index(:practice_question_options, [:practice_question_id, :position])

    create constraint(
             :practice_question_options,
             :practice_question_options_position_must_be_positive,
             check: "position > 0"
           )
  end
end
