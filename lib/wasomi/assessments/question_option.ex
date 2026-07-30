defmodule Wasomi.Assessments.QuestionOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "question_options" do
    field :label, :string
    field :correct, :boolean, default: false
    field :position, :integer

    belongs_to :question, Wasomi.Assessments.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question_option, attrs) do
    question_option
    |> cast(attrs, [:label, :correct, :position, :question_id])
    |> validate_required([:label, :position])
    |> validate_length(:label, min: 1, max: 500)
    |> validate_number(:position, greater_than: 0)
    |> check_constraint(:position, name: :question_options_position_must_be_positive)
  end
end
