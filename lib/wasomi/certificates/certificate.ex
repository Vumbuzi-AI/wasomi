defmodule Wasomi.Certificates.Certificate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "certificates" do
    field :type, Ecto.Enum, values: [:course]
    field :serial_number, :string
    field :file_key, :string
    field :issued_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(certificate, attrs) do
    certificate
    |> cast(attrs, [
      :type,
      :serial_number,
      :file_key,
      :issued_at,
      :user_id,
      :course_id
    ])
    |> validate_required([:type, :serial_number, :file_key, :issued_at, :user_id, :course_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> unique_constraint(:serial_number)
    |> unique_constraint([:user_id, :course_id], name: :certificates_unique_course_scope)
  end
end
