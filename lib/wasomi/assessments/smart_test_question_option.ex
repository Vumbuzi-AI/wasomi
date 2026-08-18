defmodule Wasomi.Assessments.SmartTestQuestionOption do
  use Ecto.Schema
  import Ecto.Changeset

  schema "smart_test_question_options" do
    field :label, :string
    field :correct, :boolean, default: false
    field :position, :integer

    belongs_to :smart_test_question, Wasomi.Assessments.SmartTestQuestion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(smart_test_question_option, attrs) do
    smart_test_question_option
    |> cast(attrs, [:label, :correct, :position, :smart_test_question_id])
    |> validate_required([:label, :position])
    |> validate_length(:label, min: 1, max: 500)
    |> validate_number(:position, greater_than: 0)
    |> check_constraint(:position, name: :smart_test_question_options_position_must_be_positive)
  end
end
