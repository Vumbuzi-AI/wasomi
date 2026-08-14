defmodule Wasomi.Assessments.PracticeQuestion do
  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Assessments.PracticeQuestionOption
  alias Wasomi.Catalog.CourseModule

  schema "practice_questions" do
    field :prompt, :string
    field :explanation, :string
    field :position, :integer
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft

    belongs_to :module, CourseModule

    has_many :practice_question_options, PracticeQuestionOption,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [:prompt, :explanation, :position, :status, :module_id])
    |> validate_required([:prompt, :position])
    |> validate_length(:prompt, min: 3, max: 2000)
    |> validate_length(:explanation, max: 4000)
    |> validate_number(:position, greater_than: 0)
    |> cast_assoc(:practice_question_options,
      with: &PracticeQuestionOption.changeset/2,
      sort_param: :practice_question_options_sort,
      drop_param: :practice_question_options_drop
    )
    |> validate_option_count()
    |> validate_correct_option()
  end

  defp validate_option_count(changeset) do
    options = get_field(changeset, :practice_question_options, [])

    if length(options) in 2..4 do
      changeset
    else
      add_error(changeset, :practice_question_options, "must have between 2 and 4 options")
    end
  end

  defp validate_correct_option(changeset) do
    options = get_field(changeset, :practice_question_options, [])

    if Enum.any?(options, & &1.correct) do
      changeset
    else
      add_error(
        changeset,
        :practice_question_options,
        "at least one option must be marked correct"
      )
    end
  end
end
