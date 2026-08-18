defmodule Wasomi.Assessments.SmartTestQuestion do
  @moduledoc """
  One question inside a `Wasomi.Assessments.SmartTest`, in one of two kinds:

    * `:multiple_choice` — carries its full option set, exactly like
      `Wasomi.Assessments.PracticeSetQuestion`.
    * `:short_answer` — carries no options; `expected_answer` is the model
      answer the learner's free text is scored against by
      `Wasomi.Catalog.LectureQuestionScorer`, which is why a short-answer
      `score` is a 0.0–1.0 float rather than a boolean.

  The learner's own response lives on this row (`response_option_id` /
  `response_text` / `score`) — see the migration for why a Smart Test needs
  no separate submissions table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Wasomi.Assessments.SmartTestQuestionOption

  @kinds [:multiple_choice, :short_answer]

  schema "smart_test_questions" do
    field :kind, Ecto.Enum, values: @kinds
    field :prompt, :string
    field :expected_answer, :string
    field :explanation, :string
    field :position, :integer

    field :response_text, :string
    field :response_option_id, :id
    field :score, :float
    field :answered_at, :utc_datetime

    belongs_to :smart_test, Wasomi.Assessments.SmartTest

    has_many :smart_test_question_options, SmartTestQuestionOption,
      foreign_key: :smart_test_question_id,
      preload_order: [asc: :position],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  @doc """
  Changeset for a generated question together with its complete option set —
  same "options are always written alongside their parent" shape as
  `Wasomi.Assessments.PracticeSetQuestion.changeset/2`, with the option set
  required for `:multiple_choice` and rejected for `:short_answer`.
  """
  def changeset(smart_test_question, attrs) do
    smart_test_question
    |> cast(attrs, [
      :kind,
      :prompt,
      :expected_answer,
      :explanation,
      :position,
      :smart_test_id
    ])
    |> validate_required([:kind, :prompt, :position, :smart_test_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:prompt, min: 3, max: 2000)
    |> validate_length(:explanation, max: 4000)
    |> cast_assoc(:smart_test_question_options, with: &SmartTestQuestionOption.changeset/2)
    |> validate_kind_shape()
    |> assoc_constraint(:smart_test)
    |> unique_constraint([:smart_test_id, :position],
      name: :smart_test_questions_smart_test_id_position_index,
      message: "has already been used in this test"
    )
    |> check_constraint(:kind, name: :smart_test_questions_kind_must_be_valid)
    |> check_constraint(:position, name: :smart_test_questions_position_must_be_positive)
  end

  @doc """
  Changeset for the learner's answer. Deliberately separate from
  `changeset/2` so answering can never rewrite the question itself, and so
  scoring stays a server-side concern: `score` is only ever set by
  `Wasomi.Assessments.finish_smart_test/2`, never by an answer event.
  """
  def response_changeset(smart_test_question, attrs) do
    smart_test_question
    |> cast(attrs, [:response_option_id, :response_text, :score, :answered_at])
    |> validate_length(:response_text, max: 5000)
    |> validate_number(:score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> check_constraint(:score, name: :smart_test_questions_score_must_be_in_range)
  end

  defp validate_kind_shape(changeset) do
    options = get_field(changeset, :smart_test_question_options) || []

    case get_field(changeset, :kind) do
      :multiple_choice -> validate_multiple_choice_options(changeset, options)
      :short_answer -> validate_short_answer(changeset, options)
      _unknown_kind -> changeset
    end
  end

  defp validate_multiple_choice_options(changeset, options) do
    cond do
      length(options) < 2 or length(options) > 4 ->
        add_error(
          changeset,
          :smart_test_question_options,
          "must have between 2 (true/false) and 4 options"
        )

      not Enum.any?(options, & &1.correct) ->
        add_error(
          changeset,
          :smart_test_question_options,
          "must include at least one correct option"
        )

      true ->
        changeset
    end
  end

  defp validate_short_answer(changeset, options) do
    changeset = validate_required(changeset, [:expected_answer])

    if options == [] do
      changeset
    else
      add_error(
        changeset,
        :smart_test_question_options,
        "cannot be set on a short-answer question"
      )
    end
  end
end
