defmodule Wasomi.Repo.Migrations.AddInReviewCourseStatus do
  use Ecto.Migration

  def change do
    drop constraint(:courses, :courses_status_must_be_valid)

    create constraint(:courses, :courses_status_must_be_valid,
             check: "status IN ('draft', 'in_review', 'published')"
           )
  end
end
