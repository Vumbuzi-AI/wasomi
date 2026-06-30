defmodule Wasomi.Catalog.CourseModule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "modules" do
    field :position, :integer
    field :description, :string
    field :title, :string
    belongs_to :course, Wasomi.Catalog.Course

    has_many :lectures, Wasomi.Catalog.Lecture,
      foreign_key: :module_id,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course_module, attrs) do
    course_module
    |> cast(attrs, [:title, :description, :position, :course_id])
    |> validate_required([:title, :description, :position, :course_id])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:course)
    |> unique_constraint([:course_id, :position],
      name: :modules_course_id_position_index,
      message: "has already been used in this course"
    )
    |> check_constraint(:position, name: :modules_position_must_be_positive)
  end
end
