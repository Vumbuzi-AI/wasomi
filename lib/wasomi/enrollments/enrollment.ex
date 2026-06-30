defmodule Wasomi.Enrollments.Enrollment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "enrollments" do
    field :status, Ecto.Enum, values: [:pending, :active], default: :pending
    field :enrolled_at, :utc_datetime
    field :activated_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [:status, :enrolled_at, :activated_at, :user_id, :course_id])
    |> validate_required([:status, :enrolled_at, :user_id, :course_id])
    |> validate_activation_state()
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> unique_constraint([:user_id, :course_id])
    |> check_constraint(:status, name: :enrollments_status_must_be_valid)
    |> check_constraint(:activated_at, name: :enrollments_activation_must_match_status)
  end

  defp validate_activation_state(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :activated_at)} do
      {:active, nil} ->
        add_error(changeset, :activated_at, "is required for an active enrollment")

      {:pending, %DateTime{}} ->
        add_error(changeset, :activated_at, "must be empty while pending")

      _ ->
        changeset
    end
  end
end
