defmodule Wasomi.Assessments.LectureQuizQuestionOption do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_quiz_question_options" do
    field :label, :string
    field :correct, :boolean, default: false
    field :position, :integer

    belongs_to :lecture_quiz_question, Wasomi.Assessments.LectureQuizQuestion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(option, attrs) do
    option
    |> cast(attrs, [:label, :correct, :position, :lecture_quiz_question_id])
    |> validate_required([:label, :position])
    |> validate_length(:label, min: 1, max: 500)
    |> validate_number(:position, greater_than: 0)
    |> check_constraint(:position,
      name: :lecture_quiz_question_options_position_must_be_positive
    )
  end
end
