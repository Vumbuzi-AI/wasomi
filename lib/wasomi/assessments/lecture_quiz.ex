defmodule Wasomi.Assessments.LectureQuiz do
  @moduledoc """
  A quiz scoped to a single lecture, distinct from the module-level `Quiz`.

  One quiz per lecture, same invariant as `Quiz`'s one-per-module — a
  separate schema rather than a nullable second FK on `Quiz`, since the two
  are generated and reviewed independently and questions from one should
  never be confusable with the other's.

  `active`/`published_at` mirror `Quiz`'s fields but aren't load-bearing yet
  — unlike the module quiz, there's no "publish the whole lecture quiz" admin
  action. A lecture quiz counts as ready for a learner (see
  `Wasomi.Assessments.lecture_quiz_ready_for_learners?/1`, used by
  `Wasomi.Learning.lecture_unlocked?/3`) as soon as it has at least one
  `:published` question — reviewing questions one at a time is enough.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_quizzes" do
    field :title, :string
    field :passing_score_percent, :integer, default: 70
    field :active, :boolean, default: false
    field :published_at, :utc_datetime

    belongs_to :lecture, Wasomi.Catalog.Lecture

    has_many :questions, Wasomi.Assessments.LectureQuizQuestion,
      foreign_key: :lecture_quiz_id,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lecture_quiz, attrs) do
    lecture_quiz
    |> cast(attrs, [:title, :passing_score_percent, :active, :published_at, :lecture_id])
    |> validate_required([:title, :passing_score_percent, :lecture_id])
    |> validate_length(:title, min: 3, max: 160)
    |> validate_number(:passing_score_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> assoc_constraint(:lecture)
    |> unique_constraint(:lecture_id, message: "already has a quiz")
    |> check_constraint(:passing_score_percent,
      name: :lecture_quizzes_passing_score_percent_must_be_valid
    )
  end
end
