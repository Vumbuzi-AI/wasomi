defmodule Wasomi.Assessments.StudyGuideSection do
  @moduledoc """
  One section of a `Wasomi.Assessments.StudyGuide` — a heading, its prose
  (`body`, paragraphs separated by blank lines), optional `bullets`, and an
  optional one-line `callout` the renderer pulls out as the section's key idea.

  Kept as structured fields rather than a blob of markup so the document is
  rendered by our own templates: the generator supplies text, never HTML.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "study_guide_sections" do
    field :heading, :string
    field :body, :string
    field :bullets, {:array, :string}, default: []
    field :callout, :string
    field :position, :integer

    belongs_to :study_guide, Wasomi.Assessments.StudyGuide

    timestamps(type: :utc_datetime)
  end

  def changeset(section, attrs) do
    section
    |> cast(attrs, [:heading, :body, :bullets, :callout, :position, :study_guide_id])
    |> validate_required([:heading, :position, :study_guide_id])
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:study_guide)
    |> unique_constraint([:study_guide_id, :position])
    |> check_constraint(:position, name: :study_guide_sections_position_must_be_positive)
  end
end
