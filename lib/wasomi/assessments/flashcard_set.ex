defmodule Wasomi.Assessments.FlashcardSet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "flashcard_sets" do
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :cards_generated_count, :integer
    field :generated_at, :utc_datetime

    belongs_to :module, Wasomi.Catalog.CourseModule, foreign_key: :module_id
    belongs_to :lecture, Wasomi.Catalog.Lecture, foreign_key: :lecture_id

    has_many :flashcards, Wasomi.Assessments.Flashcard, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(flashcard_set, attrs) do
    flashcard_set
    |> cast(attrs, [
      :status,
      :error_message,
      :cards_generated_count,
      :generated_at,
      :module_id,
      :lecture_id
    ])
    |> validate_required([:status])
    |> validate_scope()
    |> assoc_constraint(:module)
    |> assoc_constraint(:lecture)
    |> unique_constraint(:module_id, message: "already has a flashcard set")
    |> unique_constraint(:lecture_id, message: "already has a flashcard set")
    |> check_constraint(:module_id, name: :flashcard_sets_scope_must_be_exclusive)
    |> check_constraint(:status, name: :flashcard_sets_status_must_be_valid)
  end

  # A set belongs to exactly one scope — a whole module or a single lecture,
  # never both, never neither. Mirrors `Wasomi.Certificates.Certificate`'s
  # `validate_scope/1`, adapted for two mutually-exclusive FKs instead of a
  # discriminator plus one conditionally-required FK.
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
