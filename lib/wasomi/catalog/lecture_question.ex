defmodule Wasomi.Catalog.LectureQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_questions" do
    field :question, :string
    field :answer, :string
    field :position, :integer
    belongs_to :lecture, Wasomi.Catalog.Lecture

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:question, :answer, :position, :lecture_id])
    |> validate_required([:question, :answer, :position, :lecture_id])
    |> validate_length(:question, min: 2, max: 500)
    |> validate_length(:answer, min: 2, max: 5_000)
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:lecture)
    |> unique_constraint([:lecture_id, :position],
      name: :lecture_questions_lecture_id_position_index
    )
  end
end
