defmodule Wasomi.Assessments.PracticeSetQuestionProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "practice_set_question_progress" do
    field :last_correct, :boolean
    field :answered_at, :utc_datetime

    belongs_to :practice_set_question, Wasomi.Assessments.PracticeSetQuestion
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(practice_set_question_progress, attrs) do
    practice_set_question_progress
    |> cast(attrs, [:last_correct, :answered_at, :practice_set_question_id, :user_id])
    |> validate_required([:last_correct, :answered_at, :practice_set_question_id, :user_id])
    |> assoc_constraint(:practice_set_question)
    |> assoc_constraint(:user)
    |> unique_constraint([:practice_set_question_id, :user_id],
      name: :practice_set_question_progress_question_id_user_id_index
    )
  end
end
