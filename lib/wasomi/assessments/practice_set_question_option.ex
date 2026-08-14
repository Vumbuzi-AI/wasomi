defmodule Wasomi.Assessments.PracticeSetQuestionOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "practice_set_question_options" do
    field :label, :string
    field :correct, :boolean, default: false
    field :position, :integer

    belongs_to :practice_set_question, Wasomi.Assessments.PracticeSetQuestion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(practice_set_question_option, attrs) do
    practice_set_question_option
    |> cast(attrs, [:label, :correct, :position, :practice_set_question_id])
    |> validate_required([:label, :position])
    |> validate_length(:label, min: 1, max: 500)
    |> validate_number(:position, greater_than: 0)
    |> check_constraint(:position, name: :practice_set_question_options_position_must_be_positive)
  end
end
