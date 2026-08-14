defmodule Wasomi.Catalog.Lecture do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lectures" do
    field :position, :integer
    field :description, :string
    field :title, :string
    field :video_provider, Ecto.Enum, values: [:mux, :cloudflare, :bunny]
    field :video_asset_id, :string
    field :duration_seconds, :integer
    belongs_to :module, Wasomi.Catalog.CourseModule
    has_many :resources, Wasomi.Catalog.LectureResource
    has_many :questions, Wasomi.Catalog.LectureQuestion
    has_one :flashcard_set, Wasomi.Assessments.FlashcardSet, foreign_key: :lecture_id
    has_one :practice_set, Wasomi.Assessments.PracticeSet, foreign_key: :lecture_id

    timestamps(type: :utc_datetime)
  end

  def video_provider_values, do: [:mux, :cloudflare, :bunny]

  @doc false
  def changeset(lecture, attrs) do
    lecture
    |> cast(attrs, [
      :title,
      :description,
      :video_provider,
      :video_asset_id,
      :duration_seconds,
      :position,
      :module_id
    ])
    |> validate_required([
      :title,
      :description,
      :position,
      :module_id
    ])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:position, greater_than: 0)
    |> validate_video_consistency()
    |> assoc_constraint(:module)
    |> unique_constraint([:module_id, :position],
      name: :lectures_module_id_position_index,
      message: "has already been used in this module"
    )
    |> unique_constraint(:title,
      name: :lectures_module_id_title_index,
      message: "is already used by another lecture in this module"
    )
    |> check_constraint(:duration_seconds, name: :lectures_duration_must_be_positive)
    |> check_constraint(:position, name: :lectures_position_must_be_positive)
    |> check_constraint(:video_provider, name: :lectures_video_provider_must_be_valid)
  end

  # A lecture no longer requires a video (it can instead carry resources —
  # see Wasomi.Catalog.create_lecture_content/3 for the "video or at least
  # one resource" rule, which needs the resources list this changeset can't
  # see on its own). What this *can* still enforce on just the lecture's own
  # fields: video_provider and video_asset_id must arrive together, never
  # one without the other, and duration_seconds is only meaningful — and
  # only required — once a real video is actually attached.
  defp validate_video_consistency(changeset) do
    provider = get_field(changeset, :video_provider)
    asset_id = get_field(changeset, :video_asset_id)
    has_provider? = not is_nil(provider)
    has_asset_id? = is_binary(asset_id) and asset_id != ""

    cond do
      has_provider? and not has_asset_id? ->
        add_error(changeset, :video_asset_id, "can't be blank when a video provider is set")

      has_asset_id? and not has_provider? ->
        add_error(changeset, :video_provider, "can't be blank when a video asset id is set")

      has_asset_id? and is_nil(get_field(changeset, :duration_seconds)) ->
        add_error(changeset, :duration_seconds, "can't be blank when a video is attached")

      true ->
        changeset
    end
  end
end
