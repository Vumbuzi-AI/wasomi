defmodule Wasomi.Repo.Migrations.CreateLectureQuestionSubmissions do
  use Ecto.Migration

  def change do
    create table(:lecture_question_submissions) do
      add :answer_text, :text, null: false
      add :similarity_score, :float, null: false
      add :scored_at, :utc_datetime, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :lecture_question_id, references(:lecture_questions, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:lecture_question_submissions, [:user_id])
    create index(:lecture_question_submissions, [:lecture_question_id])
    create index(:lecture_question_submissions, [:user_id, :lecture_question_id])

    create constraint(
             :lecture_question_submissions,
             :lecture_question_submissions_score_range,
             check: "similarity_score >= 0.0 AND similarity_score <= 1.0"
           )
  end
end
