defmodule Wasomi.Repo.Migrations.CreatePracticeSets do
  use Ecto.Migration

  def change do
    create table(:practice_sets) do
      add :module_id, references(:modules, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :questions_generated_count, :integer
      add :generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:practice_sets, [:module_id])

    create constraint(:practice_sets, :practice_sets_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    create table(:practice_set_questions) do
      add :practice_set_id, references(:practice_sets, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :explanation, :text
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:practice_set_questions, [:practice_set_id, :position])

    create unique_index(
             :practice_set_questions,
             [:practice_set_id, "lower(trim(prompt))"],
             name: :practice_set_questions_practice_set_id_prompt_index
           )

    create constraint(:practice_set_questions, :practice_set_questions_position_must_be_positive,
             check: "position > 0"
           )

    create table(:practice_set_question_options) do
      add :practice_set_question_id,
          references(:practice_set_questions, on_delete: :delete_all),
          null: false

      add :label, :text, null: false
      add :correct, :boolean, null: false, default: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :practice_set_question_options,
             [:practice_set_question_id, :position],
             name: :practice_set_question_options_question_id_position_index
           )

    create constraint(
             :practice_set_question_options,
             :practice_set_question_options_position_must_be_positive,
             check: "position > 0"
           )

    create table(:practice_set_question_progress) do
      add :practice_set_question_id,
          references(:practice_set_questions, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :last_correct, :boolean, null: false
      add :answered_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:practice_set_question_progress, [:practice_set_question_id, :user_id],
             name: :practice_set_question_progress_question_id_user_id_index
           )
  end
end
