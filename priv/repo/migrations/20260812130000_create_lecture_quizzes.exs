defmodule Wasomi.Repo.Migrations.CreateLectureQuizzes do
  use Ecto.Migration

  def change do
    create table(:lecture_quizzes) do
      add :lecture_id, references(:lectures, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :active, :boolean, null: false, default: false
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lecture_quizzes, [:lecture_id])

    create table(:lecture_quiz_questions) do
      add :lecture_quiz_id, references(:lecture_quizzes, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lecture_quiz_questions, [:lecture_quiz_id, :position])

    create unique_index(:lecture_quiz_questions, [:lecture_quiz_id, "lower(trim(prompt))"],
             name: :lecture_quiz_questions_lecture_quiz_id_prompt_index
           )

    create constraint(
             :lecture_quiz_questions,
             :lecture_quiz_questions_position_must_be_positive,
             check: "position > 0"
           )

    create constraint(:lecture_quiz_questions, :lecture_quiz_questions_status_must_be_valid,
             check: "status IN ('draft', 'published')"
           )

    create table(:lecture_quiz_question_options) do
      add :lecture_quiz_question_id,
          references(:lecture_quiz_questions, on_delete: :delete_all),
          null: false

      add :label, :text, null: false
      add :correct, :boolean, null: false, default: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lecture_quiz_question_options, [:lecture_quiz_question_id, :position],
             name: :lecture_quiz_question_options_question_id_position_index
           )

    create constraint(
             :lecture_quiz_question_options,
             :lecture_quiz_question_options_position_must_be_positive,
             check: "position > 0"
           )

    create table(:lecture_quiz_generations) do
      add :lecture_quiz_id, references(:lecture_quizzes, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :questions_generated_count, :integer
      add :difficulty, :string, null: false, default: "mixed"
      add :question_count_requested, :integer, null: false
      add :resource_selection, {:array, :string}, null: false, default: []
      add :source_label, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_quiz_generations, [:lecture_quiz_id])

    create constraint(
             :lecture_quiz_generations,
             :lecture_quiz_generations_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    create constraint(
             :lecture_quiz_generations,
             :lecture_quiz_generations_difficulty_must_be_valid,
             check: "difficulty IN ('easy', 'medium', 'hard', 'mixed')"
           )

    create constraint(
             :lecture_quiz_generations,
             :lecture_quiz_generations_question_count_requested_must_be_valid,
             check: "question_count_requested >= 3 AND question_count_requested <= 25"
           )

    alter table(:lecture_quiz_questions) do
      add :lecture_quiz_generation_id,
          references(:lecture_quiz_generations, on_delete: :nilify_all)
    end

    create index(:lecture_quiz_questions, [:lecture_quiz_generation_id])
  end
end
