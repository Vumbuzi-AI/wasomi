defmodule Wasomi.Catalog.LectureQuestionSubmission do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_question_submissions" do
    field :answer_text, :string
    field :similarity_score, :float
    field :scored_at, :utc_datetime

    belongs_to :user, Wasomi.Accounts.User
    belongs_to :lecture_question, Wasomi.Catalog.LectureQuestion

    timestamps(type: :utc_datetime)
  end

  def changeset(submission, attrs) do
    submission
    |> cast(attrs, [:user_id, :lecture_question_id, :answer_text, :similarity_score, :scored_at])
    |> validate_required([
      :user_id,
      :lecture_question_id,
      :answer_text,
      :similarity_score,
      :scored_at
    ])
    |> validate_length(:answer_text, min: 1, max: 10_000)
    |> validate_number(:similarity_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> assoc_constraint(:user)
    |> assoc_constraint(:lecture_question)
  end
end
