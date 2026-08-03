defmodule Wasomi.Enrollments.EnrollmentAudit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "enrollment_audits" do
    field :reason, :string
    belongs_to :enrollment, Wasomi.Enrollments.Enrollment
    belongs_to :admin_user, Wasomi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(enrollment_audit, attrs) do
    enrollment_audit
    |> cast(attrs, [:reason, :enrollment_id, :admin_user_id])
    |> validate_required([:reason, :enrollment_id, :admin_user_id])
    |> validate_length(:reason, min: 10, max: 500)
    |> assoc_constraint(:enrollment)
    |> assoc_constraint(:admin_user)
  end
end
