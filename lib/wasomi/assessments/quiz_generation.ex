defmodule Wasomi.Assessments.QuizGeneration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quiz_generations" do
    field :source_filename, :string
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :questions_generated_count, :integer

    belongs_to :quiz, Wasomi.Assessments.Quiz
    belongs_to :requested_by, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(quiz_generation, attrs) do
    quiz_generation
    |> cast(attrs, [
      :source_filename,
      :status,
      :error_message,
      :questions_generated_count,
      :quiz_id,
      :requested_by_id
    ])
    |> validate_required([:source_filename, :status, :quiz_id, :requested_by_id])
    |> assoc_constraint(:quiz)
    |> assoc_constraint(:requested_by)
    |> check_constraint(:status, name: :quiz_generations_status_must_be_valid)
  end
end
