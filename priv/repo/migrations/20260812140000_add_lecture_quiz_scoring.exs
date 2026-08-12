defmodule Wasomi.Repo.Migrations.AddLectureQuizScoring do
  use Ecto.Migration

  def change do
    alter table(:lecture_quizzes) do
      add :passing_score_percent, :integer, null: false, default: 70
    end

    create constraint(
             :lecture_quizzes,
             :lecture_quizzes_passing_score_percent_must_be_valid,
             check: "passing_score_percent >= 0 AND passing_score_percent <= 100"
           )

    create table(:lecture_quiz_submissions) do
      add :lecture_quiz_id, references(:lecture_quizzes, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :answers, :map, null: false, default: %{}
      add :score_percent, :integer, null: false
      add :passed, :boolean, null: false
      add :submitted_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_quiz_submissions, [:user_id, :lecture_quiz_id])

    create constraint(
             :lecture_quiz_submissions,
             :lecture_quiz_submissions_score_percent_must_be_valid,
             check: "score_percent >= 0 AND score_percent <= 100"
           )
  end
end
