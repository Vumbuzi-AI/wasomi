defmodule Wasomi.Assessments.LectureQuizGeneration do
  @moduledoc """
  One AI generation attempt for a lecture quiz.

  Unlike `Wasomi.Assessments.QuizGeneration` (source is always exactly one
  admin-uploaded PDF), a lecture quiz can draw on several resources at once
  — `resource_selection` is the admin's picker choices verbatim (the string
  `"video"` for the lecture's transcript, or a `Wasomi.Catalog.LectureResource`
  id), and `source_label` is a human-readable summary of that same list for
  display in generation history.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_quiz_generations" do
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :questions_generated_count, :integer
    field :difficulty, Ecto.Enum, values: [:easy, :medium, :hard, :mixed], default: :mixed
    field :question_count_requested, :integer
    field :resource_selection, {:array, :string}, default: []
    field :source_label, :string

    belongs_to :lecture_quiz, Wasomi.Assessments.LectureQuiz
    belongs_to :requested_by, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(generation, attrs) do
    generation
    |> cast(attrs, [
      :status,
      :error_message,
      :questions_generated_count,
      :difficulty,
      :question_count_requested,
      :resource_selection,
      :source_label,
      :lecture_quiz_id,
      :requested_by_id
    ])
    |> validate_required([
      :status,
      :difficulty,
      :question_count_requested,
      :resource_selection,
      :source_label,
      :lecture_quiz_id,
      :requested_by_id
    ])
    |> validate_resource_selection()
    |> validate_number(:question_count_requested,
      greater_than_or_equal_to: 3,
      less_than_or_equal_to: 25
    )
    |> assoc_constraint(:lecture_quiz)
    |> assoc_constraint(:requested_by)
    |> check_constraint(:status, name: :lecture_quiz_generations_status_must_be_valid)
    |> check_constraint(:difficulty, name: :lecture_quiz_generations_difficulty_must_be_valid)
    |> check_constraint(:question_count_requested,
      name: :lecture_quiz_generations_question_count_requested_must_be_valid
    )
  end

  # A plain `validate_length(:resource_selection, min: 1, ...)` would silently
  # never run here: `Ecto.Changeset.validate_length/3` only validates fields
  # present in `changes`, and casting `[]` onto a fresh struct whose schema
  # default is already `[]` never counts as a change. `get_field/2`, unlike
  # `get_change/2`, falls back to reading the (still-empty) default, so this
  # actually catches the empty-selection case.
  defp validate_resource_selection(changeset) do
    case get_field(changeset, :resource_selection) do
      list when is_list(list) and list != [] -> changeset
      _ -> add_error(changeset, :resource_selection, "choose at least one resource")
    end
  end
end
