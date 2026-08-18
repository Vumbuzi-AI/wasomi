defmodule Wasomi.Repo.Migrations.CreateSmartTests do
  use Ecto.Migration

  def change do
    # Unlike flashcard_sets/practice_sets — one shared, learner-agnostic set
    # per scope — a Smart Test is built to one learner's own settings
    # (duration, question mix, difficulty), so it is per-user by design and
    # there is no uniqueness constraint on the scope: creating another test
    # for the same lesson is the "retake with different settings" flow.
    create table(:smart_tests) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :module_id, references(:modules, on_delete: :delete_all)
      add :lecture_id, references(:lectures, on_delete: :delete_all)

      add :duration_minutes, :integer, null: false
      add :enforce_time_limit, :boolean, null: false, default: true
      add :multiple_choice_count, :integer, null: false
      add :short_answer_count, :integer, null: false
      add :difficulty, :integer, null: false

      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :questions_generated_count, :integer
      add :generated_at, :utc_datetime

      add :started_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :paused_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :score_percent, :integer
      add :time_expired, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:smart_tests, [:user_id, :module_id])
    create index(:smart_tests, [:user_id, :lecture_id])

    create constraint(:smart_tests, :smart_tests_scope_must_be_exclusive,
             check: "(module_id IS NOT NULL) <> (lecture_id IS NOT NULL)"
           )

    create constraint(:smart_tests, :smart_tests_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    create constraint(:smart_tests, :smart_tests_difficulty_must_be_in_range,
             check: "difficulty BETWEEN 1 AND 5"
           )

    create constraint(:smart_tests, :smart_tests_duration_must_be_positive,
             check: "duration_minutes > 0"
           )

    create constraint(:smart_tests, :smart_tests_must_have_a_question,
             check:
               "multiple_choice_count >= 0 AND short_answer_count >= 0 AND (multiple_choice_count + short_answer_count) > 0"
           )

    # The learner's own response lives on the question row rather than in a
    # separate submissions table: a Smart Test belongs to exactly one learner
    # and holds exactly one attempt (a retake is a new test), so there is
    # never more than one response per question to store.
    create table(:smart_test_questions) do
      add :smart_test_id, references(:smart_tests, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :prompt, :text, null: false
      add :expected_answer, :text
      add :explanation, :text
      add :position, :integer, null: false

      add :response_text, :text
      add :score, :float
      add :answered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:smart_test_questions, [:smart_test_id, :position])

    create constraint(:smart_test_questions, :smart_test_questions_kind_must_be_valid,
             check: "kind IN ('multiple_choice', 'short_answer')"
           )

    create constraint(:smart_test_questions, :smart_test_questions_position_must_be_positive,
             check: "position > 0"
           )

    create constraint(:smart_test_questions, :smart_test_questions_score_must_be_in_range,
             check: "score IS NULL OR (score >= 0 AND score <= 1)"
           )

    create table(:smart_test_question_options) do
      add :smart_test_question_id,
          references(:smart_test_questions, on_delete: :delete_all),
          null: false

      add :label, :text, null: false
      add :correct, :boolean, null: false, default: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :smart_test_question_options,
             [:smart_test_question_id, :position],
             name: :smart_test_question_options_question_id_position_index
           )

    create constraint(
             :smart_test_question_options,
             :smart_test_question_options_position_must_be_positive,
             check: "position > 0"
           )

    # Added after the options table exists, since the reference points the
    # opposite way to the parent/child relationship above.
    alter table(:smart_test_questions) do
      add :response_option_id,
          references(:smart_test_question_options, on_delete: :nilify_all)
    end
  end
end
