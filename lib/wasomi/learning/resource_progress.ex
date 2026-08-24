defmodule Wasomi.Learning.ResourceProgress do
  @moduledoc """
  One learner's "I have read this" mark against a single lecture resource.

  The counterpart to `Wasomi.Learning.LectureProgress` for material that can't
  report on itself. A video emits playback positions, so completion can be
  derived; a PDF emits nothing the server can trust, so reading it is an
  explicit act — the learner clicks "Mark as read" and this row is written.

  There is no `status`: the row's existence *is* the completed state, so there
  is no half-read state to keep consistent, and un-marking is a delete.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "resource_progress" do
    field :completed_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :lecture_resource, Wasomi.Catalog.LectureResource

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(resource_progress, attrs) do
    resource_progress
    |> cast(attrs, [:completed_at, :user_id, :lecture_resource_id])
    |> validate_required([:completed_at, :user_id, :lecture_resource_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:lecture_resource)
    |> unique_constraint([:user_id, :lecture_resource_id])
  end
end
