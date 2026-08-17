defmodule Wasomi.Assessments.FlashcardProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcard_progress" do
    field :status, Ecto.Enum, values: [:unseen, :known, :review_again], default: :unseen
    field :reviewed_at, :utc_datetime

    belongs_to :flashcard, Wasomi.Assessments.Flashcard
    belongs_to :user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard_progress, attrs) do
    flashcard_progress
    |> cast(attrs, [:status, :reviewed_at, :flashcard_id, :user_id])
    |> validate_required([:status, :reviewed_at, :flashcard_id, :user_id])
    |> assoc_constraint(:flashcard)
    |> assoc_constraint(:user)
    |> unique_constraint([:flashcard_id, :user_id],
      name: :flashcard_progress_flashcard_id_user_id_index
    )
    |> check_constraint(:status, name: :flashcard_progress_status_must_be_valid)
  end
end
