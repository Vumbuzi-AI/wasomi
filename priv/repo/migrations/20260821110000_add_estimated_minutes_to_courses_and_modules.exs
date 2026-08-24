defmodule Wasomi.Repo.Migrations.AddEstimatedMinutesToCoursesAndModules do
  use Ecto.Migration

  def change do
    # "Learning time" on the learner side was summed from video durations alone,
    # which undercounts every course: it ignores the PDFs to read, the practice
    # questions to answer and the quizzes to sit. An admin knows the real figure,
    # so they can now state it, per course and per module, and the learner sees
    # that instead of the video-only sum whenever it is set.
    alter table(:courses) do
      add :estimated_minutes, :integer
    end

    alter table(:modules) do
      add :estimated_minutes, :integer
    end

    create constraint(:courses, :courses_estimated_minutes_must_be_positive,
             check: "estimated_minutes IS NULL OR estimated_minutes > 0"
           )

    create constraint(:modules, :modules_estimated_minutes_must_be_positive,
             check: "estimated_minutes IS NULL OR estimated_minutes > 0"
           )
  end
end

