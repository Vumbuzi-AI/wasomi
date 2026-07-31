defmodule Wasomi.Assessments.Question do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Assessments.QuestionOption

  schema "questions" do
    field :prompt, :string
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft
    field :position, :integer

    belongs_to :quiz, Wasomi.Assessments.Quiz
    belongs_to :quiz_generation, Wasomi.Assessments.QuizGeneration

    has_many :question_options, QuestionOption,
      foreign_key: :question_id,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a question together with its full set of options.

  Options are always written as a complete set alongside their parent
  question — there is no standalone create/update path for a single option
  (see `Wasomi.Assessments` moduledoc). That keeps "does this question have
  at least one correct option" checkable from the attrs alone, with no need
  to read sibling rows back from the database first.
  """
  def changeset(question, attrs) do
    question
    |> cast(attrs, [:prompt, :status, :position, :quiz_id, :quiz_generation_id])
    |> validate_required([:prompt, :status, :position, :quiz_id])
    |> validate_length(:prompt, min: 3, max: 2000)
    |> cast_assoc(:question_options,
      with: &QuestionOption.changeset/2,
      required: true
    )
    |> validate_length(:question_options,
      min: 2,
      max: 4,
      message: "must have between 2 (true/false) and 4 options"
    )
    |> validate_has_correct_option()
    |> assoc_constraint(:quiz)
    |> assoc_constraint(:quiz_generation)
    |> unique_constraint([:quiz_id, :position],
      name: :questions_quiz_id_position_index,
      message: "has already been used in this quiz"
    )
    |> unique_constraint(:prompt,
      name: :questions_quiz_id_prompt_index,
      message: "already exists in this quiz"
    )
    |> check_constraint(:position, name: :questions_position_must_be_positive)
    |> check_constraint(:status, name: :questions_status_must_be_valid)
  end

  defp validate_has_correct_option(changeset) do
    options = get_field(changeset, :question_options) || []

    if options == [] or Enum.any?(options, & &1.correct) do
      changeset
    else
      add_error(changeset, :question_options, "must include at least one correct option")
    end
  end
end
