defmodule Wasomi.Assessments.Quiz do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quizzes" do
    field :title, :string
    field :description, :string
    field :passing_score_percent, :integer, default: 70
    field :active, :boolean, default: false
    field :published_at, :utc_datetime

    belongs_to :module, Wasomi.Catalog.CourseModule, foreign_key: :module_id

    has_many :questions, Wasomi.Assessments.Question, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(quiz, attrs) do
    quiz
    |> cast(attrs, [
      :title,
      :description,
      :passing_score_percent,
      :active,
      :published_at,
      :module_id
    ])
    |> validate_required([:title, :passing_score_percent, :module_id])
    |> validate_length(:title, min: 3, max: 160)
    |> validate_number(:passing_score_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> assoc_constraint(:module)
    |> unique_constraint(:module_id, message: "already has a quiz")
    |> check_constraint(:passing_score_percent,
      name: :quizzes_passing_score_percent_must_be_valid
    )
  end
end
