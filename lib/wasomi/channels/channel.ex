defmodule Wasomi.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    belongs_to :course, Wasomi.Catalog.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:course_id])
    |> validate_required([:course_id])
    |> assoc_constraint(:course)
    |> unique_constraint(:course_id)
  end
end
