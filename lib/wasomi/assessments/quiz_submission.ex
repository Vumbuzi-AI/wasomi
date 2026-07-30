defmodule Wasomi.Assessments.QuizSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quiz_submissions" do
    field :answers, :map, default: %{}
    field :score_percent, :integer
    field :passed, :boolean
    field :submitted_at, :utc_datetime

    belongs_to :quiz, Wasomi.Assessments.Quiz
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(quiz_submission, attrs) do
    quiz_submission
    |> cast(attrs, [:answers, :score_percent, :passed, :submitted_at, :quiz_id, :user_id])
    |> validate_required([:answers, :score_percent, :passed, :submitted_at, :quiz_id, :user_id])
    |> validate_number(:score_percent,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> assoc_constraint(:quiz)
    |> assoc_constraint(:user)
    |> check_constraint(:score_percent, name: :quiz_submissions_score_percent_must_be_valid)
  end
end
