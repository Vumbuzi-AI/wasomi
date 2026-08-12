defmodule Wasomi.Assessments.LectureQuizQuestion do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Assessments.LectureQuizQuestionOption

  schema "lecture_quiz_questions" do
    field :prompt, :string
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft
    field :position, :integer

    belongs_to :lecture_quiz, Wasomi.Assessments.LectureQuiz
    belongs_to :lecture_quiz_generation, Wasomi.Assessments.LectureQuizGeneration

    has_many :question_options, LectureQuizQuestionOption,
      foreign_key: :lecture_quiz_question_id,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :prompt,
      :status,
      :position,
      :lecture_quiz_id,
      :lecture_quiz_generation_id
    ])
    |> validate_required([:prompt, :status, :position, :lecture_quiz_id])
    |> validate_length(:prompt, min: 3, max: 2000)
    |> cast_assoc(:question_options,
      with: &LectureQuizQuestionOption.changeset/2,
      required: true
    )
    |> validate_length(:question_options,
      min: 2,
      max: 4,
      message: "must have between 2 (true/false) and 4 options"
    )
    |> validate_has_correct_option()
    |> assoc_constraint(:lecture_quiz)
    |> assoc_constraint(:lecture_quiz_generation)
    |> unique_constraint([:lecture_quiz_id, :position],
      name: :lecture_quiz_questions_lecture_quiz_id_position_index,
      message: "has already been used in this quiz"
    )
    |> unique_constraint(:prompt,
      name: :lecture_quiz_questions_lecture_quiz_id_prompt_index,
      message: "already exists in this quiz"
    )
    |> check_constraint(:position, name: :lecture_quiz_questions_position_must_be_positive)
    |> check_constraint(:status, name: :lecture_quiz_questions_status_must_be_valid)
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
