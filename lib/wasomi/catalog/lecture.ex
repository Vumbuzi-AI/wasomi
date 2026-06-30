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

    timestamps(type: :utc_datetime)
  end

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
      :video_provider,
      :video_asset_id,
      :duration_seconds,
      :position,
      :module_id
    ])
    |> validate_length(:title, min: 2, max: 160)
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_number(:position, greater_than: 0)
    |> assoc_constraint(:module)
    |> unique_constraint([:module_id, :position],
      name: :lectures_module_id_position_index,
      message: "has already been used in this module"
    )
    |> check_constraint(:duration_seconds, name: :lectures_duration_must_be_positive)
    |> check_constraint(:position, name: :lectures_position_must_be_positive)
    |> check_constraint(:video_provider, name: :lectures_video_provider_must_be_valid)
  end
end
