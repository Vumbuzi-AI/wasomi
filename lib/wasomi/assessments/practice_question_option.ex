defmodule Wasomi.Assessments.PracticeQuestionOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "practice_question_options" do
    field :label, :string
    field :correct, :boolean, default: false
    field :position, :integer

    belongs_to :practice_question, Wasomi.Assessments.PracticeQuestion

    timestamps(type: :utc_datetime)
  end

  def changeset(option, attrs) do
    option
    |> cast(attrs, [:label, :correct, :position, :practice_question_id])
    |> validate_required([:label, :position])
    |> validate_length(:label, min: 1, max: 500)
    |> validate_number(:position, greater_than: 0)
  end
end
