defmodule Wasomi.Assessments.LectureQuiz do
  @moduledoc """
  A quiz scoped to a single lecture, distinct from the module-level `Quiz`.

  One quiz per lecture, same invariant as `Quiz`'s one-per-module — a
  separate schema rather than a nullable second FK on `Quiz`, since the two
  are generated and reviewed independently and questions from one should
  never be confusable with the other's.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_quizzes" do
    field :title, :string
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
    |> cast(attrs, [:title, :active, :published_at, :lecture_id])
    |> validate_required([:title, :lecture_id])
    |> validate_length(:title, min: 3, max: 160)
    |> assoc_constraint(:lecture)
    |> unique_constraint(:lecture_id, message: "already has a quiz")
  end
end
