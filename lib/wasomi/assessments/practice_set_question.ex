defmodule Wasomi.Assessments.PracticeSetQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Assessments.PracticeSetQuestionOption

  schema "practice_set_questions" do
    field :prompt, :string
    field :explanation, :string
    field :position, :integer

    belongs_to :practice_set, Wasomi.Assessments.PracticeSet

    has_many :practice_set_question_options, PracticeSetQuestionOption,
      foreign_key: :practice_set_question_id,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a practice question together with its full set of options.

  Same "options are always written as a complete set alongside their
  parent" shape as `Wasomi.Assessments.Question.changeset/2` — there is no
  standalone create/update path for a single option.
  """
  def changeset(practice_set_question, attrs) do
    practice_set_question
    |> cast(attrs, [:prompt, :explanation, :position, :practice_set_id])
    |> validate_required([:prompt, :position, :practice_set_id])
    |> validate_length(:prompt, min: 3, max: 2000)
    |> validate_length(:explanation, max: 4000)
    |> cast_assoc(:practice_set_question_options,
      with: &PracticeSetQuestionOption.changeset/2,
      required: true
    )
    |> validate_length(:practice_set_question_options,
      min: 2,
      max: 4,
      message: "must have between 2 (true/false) and 4 options"
    )
    |> validate_has_correct_option()
    |> assoc_constraint(:practice_set)
    |> unique_constraint([:practice_set_id, :position],
      name: :practice_set_questions_practice_set_id_position_index,
      message: "has already been used in this practice set"
    )
    |> unique_constraint(:prompt,
      name: :practice_set_questions_practice_set_id_prompt_index,
      message: "already exists in this practice set"
    )
    |> check_constraint(:position, name: :practice_set_questions_position_must_be_positive)
  end

  defp validate_has_correct_option(changeset) do
    options = get_field(changeset, :practice_set_question_options) || []

    if options == [] or Enum.any?(options, & &1.correct) do
      changeset
    else
      add_error(
        changeset,
        :practice_set_question_options,
        "must include at least one correct option"
      )
    end
  end
end
