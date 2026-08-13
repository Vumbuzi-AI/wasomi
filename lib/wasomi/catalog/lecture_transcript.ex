defmodule Wasomi.Catalog.LectureTranscript do
  @moduledoc """
  Speech-to-text transcript of a lecture's primary video.

  Kept as its own 1:1 table rather than a field on `Lecture` because
  `Catalog.update_lecture_content/4` wholesale-deletes and reinserts the
  lecture's resources/questions on every admin save — a transcript field on
  `Lecture` would either need to survive that dance untouched (fragile) or
  get wiped by an unrelated edit.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_transcripts" do
    field :status, Ecto.Enum, values: [:pending, :processing, :ready, :failed], default: :pending
    field :text, :string
    field :error, :string
    belongs_to :lecture, Wasomi.Catalog.Lecture

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, [:status, :text, :error, :lecture_id])
    |> validate_required([:status, :lecture_id])
    |> assoc_constraint(:lecture)
    |> unique_constraint(:lecture_id)
  end
end
