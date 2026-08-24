defmodule Wasomi.Catalog.CourseModule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "modules" do
    field :position, :integer
    field :description, :string
    field :title, :string
    # Same optional admin estimate as `Wasomi.Catalog.Course.estimated_minutes`,
    # scoped to this module. Falls back to the sum of its lectures' video
    # durations when blank.
    field :estimated_minutes, :integer
    belongs_to :course, Wasomi.Catalog.Course

    has_many :lectures, Wasomi.Catalog.Lecture,
      foreign_key: :module_id,
      preload_order: [asc: :position]

    has_one :quiz, Wasomi.Assessments.Quiz, foreign_key: :module_id
    has_one :flashcard_set, Wasomi.Assessments.FlashcardSet, foreign_key: :module_id
    has_one :practice_set, Wasomi.Assessments.PracticeSet, foreign_key: :module_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course_module, attrs) do
    course_module
    |> cast(attrs, [:title, :description, :position, :course_id, :estimated_minutes])
    |> validate_required([:title, :description, :position, :course_id])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_number(:position, greater_than: 0)
    |> validate_number(:estimated_minutes, greater_than: 0)
    |> assoc_constraint(:course)
    |> unique_constraint([:course_id, :position],
      name: :modules_course_id_position_index,
      message: "has already been used in this course"
    )
    |> unique_constraint(:title,
      name: :modules_course_id_title_index,
      message: "is already used by another module in this course"
    )
    |> check_constraint(:position, name: :modules_position_must_be_positive)
    |> check_constraint(:estimated_minutes, name: :modules_estimated_minutes_must_be_positive)
  end
end

