defmodule Wasomi.Assessments.StudyGuide do
  @moduledoc """
  One learner-commissioned set of study notes over a module or a single
  lecture — the "Study guide" mode of `WasomiWeb.StudyHubLive`.

  Like `Wasomi.Assessments.SmartTest` (and unlike the shared, learner-agnostic
  `FlashcardSet`/`PracticeSet`), a guide belongs to a user and carries the
  brief they wrote it against: a `style` (the same material told as a story
  reads nothing like the same material as a cheat sheet), a `depth`, a
  `reading_level`, whether to include worked examples and a glossary, and an
  optional free-text `focus`. Asking for another style is a new guide, not an
  overwrite, so a learner can keep the story *and* the cheat sheet.

  The generated document lives in structured fields — `title`, `summary`,
  `key_takeaways`, embedded `key_terms`, and `Wasomi.Assessments.StudyGuideSection`
  rows — rather than as model-authored HTML, so rendering stays ours and no
  markup from the model is ever trusted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @styles [:story, :notes, :cheat_sheet, :q_and_a, :analogies]
  @depths [:brief, :standard, :deep]
  @reading_levels [:beginner, :intermediate, :advanced]
  @max_focus_chars 500

  schema "study_guides" do
    field :style, Ecto.Enum, values: @styles
    field :depth, Ecto.Enum, values: @depths, default: :standard
    field :reading_level, Ecto.Enum, values: @reading_levels, default: :intermediate
    field :include_key_terms, :boolean, default: true
    field :include_examples, :boolean, default: true
    field :focus, :string

    field :title, :string
    field :summary, :string
    field :key_takeaways, {:array, :string}, default: []

    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :sections_generated_count, :integer
    field :generated_at, :utc_datetime

    embeds_many :key_terms, Term, on_replace: :delete, primary_key: false do
      field :term, :string
      field :definition, :string
    end

    belongs_to :user, Wasomi.Accounts.User
    belongs_to :module, Wasomi.Catalog.CourseModule, foreign_key: :module_id
    belongs_to :lecture, Wasomi.Catalog.Lecture, foreign_key: :lecture_id

    has_many :study_guide_sections, Wasomi.Assessments.StudyGuideSection,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Bounds every learner-chosen setting, since they arrive straight from a form:
  the style/depth/reading-level dials are closed sets, and `focus` is trimmed
  to something a prompt can carry.
  """
  def changeset(study_guide, attrs) do
    study_guide
    |> cast(attrs, [
      :style,
      :depth,
      :reading_level,
      :include_key_terms,
      :include_examples,
      :focus,
      :title,
      :summary,
      :key_takeaways,
      :status,
      :error_message,
      :sections_generated_count,
      :generated_at,
      :user_id,
      :module_id,
      :lecture_id
    ])
    |> cast_embed(:key_terms, with: &term_changeset/2)
    |> update_change(:focus, &trim_focus/1)
    |> validate_required([:style, :depth, :reading_level, :status, :user_id])
    |> validate_inclusion(:style, @styles)
    |> validate_inclusion(:depth, @depths)
    |> validate_inclusion(:reading_level, @reading_levels)
    |> validate_scope()
    |> assoc_constraint(:user)
    |> assoc_constraint(:module)
    |> assoc_constraint(:lecture)
    |> check_constraint(:module_id, name: :study_guides_scope_must_be_exclusive)
    |> check_constraint(:status, name: :study_guides_status_must_be_valid)
    |> check_constraint(:style, name: :study_guides_style_must_be_valid)
    |> check_constraint(:depth, name: :study_guides_depth_must_be_valid)
    |> check_constraint(:reading_level, name: :study_guides_reading_level_must_be_valid)
  end

  @doc "The settings the UI is allowed to offer, so form and schema can't drift."
  def styles, do: @styles
  def depths, do: @depths
  def reading_levels, do: @reading_levels
  def max_focus_chars, do: @max_focus_chars

  defp term_changeset(term, attrs) do
    term
    |> cast(attrs, [:term, :definition])
    |> validate_required([:term, :definition])
  end

  defp trim_focus(nil), do: nil

  defp trim_focus(focus) when is_binary(focus) do
    case String.trim(focus) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, @max_focus_chars)
    end
  end

  defp trim_focus(focus), do: focus

  # Mirrors `Wasomi.Assessments.SmartTest.validate_scope/1` — exactly one of
  # module_id/lecture_id, never both, never neither.
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
