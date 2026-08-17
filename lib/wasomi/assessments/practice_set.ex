defmodule Wasomi.Assessments.PracticeSet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "practice_sets" do
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :questions_generated_count, :integer
    field :generated_at, :utc_datetime

    belongs_to :module, Wasomi.Catalog.CourseModule, foreign_key: :module_id
    belongs_to :lecture, Wasomi.Catalog.Lecture, foreign_key: :lecture_id

    has_many :practice_set_questions, Wasomi.Assessments.PracticeSetQuestion,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(practice_set, attrs) do
    practice_set
    |> cast(attrs, [
      :status,
      :error_message,
      :questions_generated_count,
      :generated_at,
      :module_id,
      :lecture_id
    ])
    |> validate_required([:status])
    |> validate_scope()
    |> assoc_constraint(:module)
    |> assoc_constraint(:lecture)
    |> unique_constraint(:module_id, message: "already has a practice set")
    |> unique_constraint(:lecture_id, message: "already has a practice set")
    |> check_constraint(:module_id, name: :practice_sets_scope_must_be_exclusive)
    |> check_constraint(:status, name: :practice_sets_status_must_be_valid)
  end

  # Mirrors `Wasomi.Assessments.FlashcardSet.validate_scope/1` — exactly one
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
