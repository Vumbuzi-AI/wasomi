defmodule Wasomi.Repo.Migrations.CreateCourseReviews do
  use Ecto.Migration

  def change do
    create table(:course_reviews) do
      add :rating, :integer, null: false
      add :body, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :course_id, references(:courses, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # One review per learner per course; editing updates the same row.
    create unique_index(:course_reviews, [:user_id, :course_id])
    create index(:course_reviews, [:course_id])

    create constraint(:course_reviews, :course_reviews_rating_between_1_and_5,
             check: "rating BETWEEN 1 AND 5"
           )
  end
end
