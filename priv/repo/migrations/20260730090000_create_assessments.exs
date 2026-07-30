defmodule Wasomi.Repo.Migrations.CreateAssessments do
  use Ecto.Migration

  def change do
    create table(:quizzes) do
      add :module_id, references(:modules, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :passing_score_percent, :integer, null: false, default: 70

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quizzes, [:module_id])

    create constraint(:quizzes, :quizzes_passing_score_percent_must_be_valid,
             check: "passing_score_percent >= 0 AND passing_score_percent <= 100"
           )

    create table(:questions) do
      add :quiz_id, references(:quizzes, on_delete: :delete_all), null: false
      add :prompt, :text, null: false
      add :status, :string, null: false, default: "draft"
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:questions, [:quiz_id, :position])

    create unique_index(:questions, [:quiz_id, "lower(trim(prompt))"],
             name: :questions_quiz_id_prompt_index
           )

    create constraint(:questions, :questions_position_must_be_positive, check: "position > 0")

    create constraint(:questions, :questions_status_must_be_valid,
             check: "status IN ('draft', 'published')"
           )

    create table(:question_options) do
      add :question_id, references(:questions, on_delete: :delete_all), null: false
      add :label, :text, null: false
      add :correct, :boolean, null: false, default: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:question_options, [:question_id, :position])

    create constraint(:question_options, :question_options_position_must_be_positive,
             check: "position > 0"
           )

    create table(:quiz_submissions) do
      add :quiz_id, references(:quizzes, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :answers, :map, null: false, default: %{}
      add :score_percent, :integer, null: false
      add :passed, :boolean, null: false
      add :submitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:quiz_submissions, [:user_id, :quiz_id])

    create constraint(:quiz_submissions, :quiz_submissions_score_percent_must_be_valid,
             check: "score_percent >= 0 AND score_percent <= 100"
           )
  end
end
