defmodule Wasomi.Assessments.SmartTest do
  @moduledoc """
  One learner-built timed test ("Smart Test") over a module or a single
  lecture.

  Unlike `Wasomi.Assessments.FlashcardSet`/`PracticeSet` — one shared set per
  scope, identical for every learner — a Smart Test carries the settings the
  learner chose (duration, how many multiple-choice vs. short-answer
  questions, difficulty), so it belongs to a user and there is no
  one-per-scope uniqueness: pressing "Create test" again simply builds
  another one.

  Both generation status (`:pending` → `:processing` → `:ready`/`:failed`)
  and attempt state (`started_at`/`expires_at`/`paused_at`/`completed_at`)
  live on this row so an interrupted attempt survives a reconnect: the
  countdown is derived from the persisted `expires_at`, never from
  socket-only state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @difficulty_range 1..5
  @max_duration_minutes 180
  @max_multiple_choice 20
  @max_short_answer 10

  schema "smart_tests" do
    field :duration_minutes, :integer
    field :enforce_time_limit, :boolean, default: true
    field :multiple_choice_count, :integer
    field :short_answer_count, :integer
    field :difficulty, :integer

    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :questions_generated_count, :integer
    field :generated_at, :utc_datetime

    field :started_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :paused_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :score_percent, :integer
    field :time_expired, :boolean, default: false

    belongs_to :user, Wasomi.Accounts.User
    belongs_to :module, Wasomi.Catalog.CourseModule, foreign_key: :module_id
    belongs_to :lecture, Wasomi.Catalog.Lecture, foreign_key: :lecture_id

    has_many :smart_test_questions, Wasomi.Assessments.SmartTestQuestion,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Bounds every learner-chosen setting, since they arrive straight from a
  form: a stepper or a hand-edited payload can't ask for a 10-hour, 500
  question test.
  """
  def changeset(smart_test, attrs) do
    smart_test
    |> cast(attrs, [
      :duration_minutes,
      :enforce_time_limit,
      :multiple_choice_count,
      :short_answer_count,
      :difficulty,
      :status,
      :error_message,
      :questions_generated_count,
      :generated_at,
      :started_at,
      :expires_at,
      :paused_at,
      :completed_at,
      :score_percent,
      :time_expired,
      :user_id,
      :module_id,
      :lecture_id
    ])
    |> validate_required([
      :duration_minutes,
      :multiple_choice_count,
      :short_answer_count,
      :difficulty,
      :status,
      :user_id
    ])
    |> validate_number(:duration_minutes,
      greater_than: 0,
      less_than_or_equal_to: @max_duration_minutes
    )
    |> validate_number(:multiple_choice_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_multiple_choice
    )
    |> validate_number(:short_answer_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: @max_short_answer
    )
    |> validate_inclusion(:difficulty, @difficulty_range)
    |> validate_number(:score_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> validate_at_least_one_question()
    |> validate_scope()
    |> assoc_constraint(:user)
    |> assoc_constraint(:module)
    |> assoc_constraint(:lecture)
    |> check_constraint(:module_id, name: :smart_tests_scope_must_be_exclusive)
    |> check_constraint(:status, name: :smart_tests_status_must_be_valid)
    |> check_constraint(:difficulty, name: :smart_tests_difficulty_must_be_in_range)
    |> check_constraint(:duration_minutes, name: :smart_tests_duration_must_be_positive)
    |> check_constraint(:multiple_choice_count, name: :smart_tests_must_have_a_question)
  end

  @doc "The settings range the UI is allowed to offer, so form and schema can't drift."
  def difficulty_range, do: @difficulty_range
  def max_duration_minutes, do: @max_duration_minutes
  def max_multiple_choice, do: @max_multiple_choice
  def max_short_answer, do: @max_short_answer

  @doc "Total questions the learner asked for, before generation trims to what the material supports."
  def requested_question_count(%__MODULE__{
        multiple_choice_count: multiple_choice,
        short_answer_count: short_answer
      }),
      do: (multiple_choice || 0) + (short_answer || 0)

  defp validate_at_least_one_question(changeset) do
    multiple_choice = get_field(changeset, :multiple_choice_count) || 0
    short_answer = get_field(changeset, :short_answer_count) || 0

    if multiple_choice + short_answer > 0 do
      changeset
    else
      add_error(changeset, :multiple_choice_count, "must ask for at least one question")
    end
  end

  # Mirrors `Wasomi.Assessments.PracticeSet.validate_scope/1` — exactly one
  # of module_id/lecture_id, never both, never neither.
  defp validate_scope(changeset) do
    case {get_field(changeset, :module_id), get_field(changeset, :lecture_id)} do
      {nil, nil} ->
        add_error(changeset, :module_id, "must set either a module or a lecture")

      {module_id, lecture_id} when not is_nil(module_id) and not is_nil(lecture_id) ->
        add_error(changeset, :lecture_id, "cannot be set together with a module")

      _ ->
        changeset
    end
  end
end
