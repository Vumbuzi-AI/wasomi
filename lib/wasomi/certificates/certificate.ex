defmodule Wasomi.Certificates.Certificate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "certificates" do
    field :type, Ecto.Enum, values: [:course]
    field :gdti, :string
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
      :gdti,
      :file_key,
      :issued_at,
      :user_id,
      :course_id
    ])
    |> validate_required([:type, :gdti, :file_key, :issued_at, :user_id, :course_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> unique_constraint(:gdti)
    |> unique_constraint([:user_id, :course_id], name: :certificates_unique_course_scope)
    |> check_constraint(:type, name: :certificates_type_must_be_valid)
  end
end
