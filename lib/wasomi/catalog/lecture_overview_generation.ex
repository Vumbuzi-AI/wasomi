defmodule Wasomi.Catalog.LectureOverviewGeneration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_overview_generations" do
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :error_message, :string
    field :scene_count, :integer
    field :video_storage_key, :string

    # Tracks turning a `:ready` generation into the lecture's actual
    # playable video (a Mux asset created from the generated file, not a
    # browser upload) — independent of `status` above, which only covers
    # the generation itself.
    field :attach_status, Ecto.Enum,
      values: [:not_attached, :attaching, :attached, :attach_failed],
      default: :not_attached

    field :attach_asset_id, :string
    field :attach_error_message, :string

    belongs_to :lecture, Wasomi.Catalog.Lecture
    belongs_to :requested_by, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(generation, attrs) do
    generation
    |> cast(attrs, [
      :status,
      :error_message,
      :scene_count,
      :video_storage_key,
      :attach_status,
      :attach_asset_id,
      :attach_error_message,
      :lecture_id,
      :requested_by_id
    ])
    |> validate_required([:status, :attach_status, :lecture_id, :requested_by_id])
    |> assoc_constraint(:lecture)
    |> assoc_constraint(:requested_by)
    |> check_constraint(:status, name: :lecture_overview_generations_status_must_be_valid)
    |> check_constraint(:attach_status,
      name: :lecture_overview_generations_attach_status_must_be_valid
    )
  end
end
