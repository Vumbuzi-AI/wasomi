defmodule Wasomi.Assessments.Flashcard do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcards" do
    field :front, :string
    field :back, :string
    field :position, :integer

    belongs_to :flashcard_set, Wasomi.Assessments.FlashcardSet

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard, attrs) do
    flashcard
    |> cast(attrs, [:front, :back, :position, :flashcard_set_id])
    |> validate_required([:front, :back, :position, :flashcard_set_id])
    |> validate_length(:front, min: 1, max: 2000)
    |> validate_length(:back, min: 1, max: 2000)
    |> assoc_constraint(:flashcard_set)
    |> unique_constraint([:flashcard_set_id, :position],
      name: :flashcards_flashcard_set_id_position_index,
      message: "has already been used in this set"
    )
    |> check_constraint(:position, name: :flashcards_position_must_be_positive)
  end
end
