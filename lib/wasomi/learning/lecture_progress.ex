defmodule Wasomi.Learning.LectureProgress do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_progress" do
    field :status, Ecto.Enum,
      values: [:not_started, :in_progress, :completed],
      default: :not_started

    field :last_position_seconds, :integer, default: 0
    field :completed_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :lecture, Wasomi.Catalog.Lecture

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lecture_progress, attrs) do
    lecture_progress
    |> cast(attrs, [
      :status,
      :last_position_seconds,
      :completed_at,
      :user_id,
      :lecture_id
    ])
    |> validate_required([:status, :last_position_seconds, :user_id, :lecture_id])
    |> validate_number(:last_position_seconds, greater_than_or_equal_to: 0)
    |> validate_completion_timestamp()
    |> assoc_constraint(:user)
    |> assoc_constraint(:lecture)
    |> unique_constraint([:user_id, :lecture_id])
    |> check_constraint(:status, name: :lecture_progress_status_must_be_valid)
    |> check_constraint(:last_position_seconds,
      name: :lecture_progress_position_must_be_non_negative
    )
  end

  defp validate_completion_timestamp(changeset) do
    case get_field(changeset, :status) do
      :completed -> validate_required(changeset, [:completed_at])
      _ -> put_change(changeset, :completed_at, nil)
    end
  end
end
