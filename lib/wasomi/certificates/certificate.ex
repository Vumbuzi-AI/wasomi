defmodule Wasomi.Certificates.Certificate do
  use Ecto.Schema
  import Ecto.Changeset

  schema "certificates" do
    field :type, Ecto.Enum, values: [:module, :course]
    field :serial_number, :string
    field :file_key, :string
    field :issued_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course
    belongs_to :module, Wasomi.Catalog.CourseModule

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
      :course_id,
      :module_id
    ])
    |> validate_required([:type, :serial_number, :file_key, :issued_at, :user_id, :course_id])
    |> validate_scope()
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> assoc_constraint(:module)
    |> unique_constraint(:serial_number)
    |> unique_constraint([:user_id, :module_id], name: :certificates_unique_module_scope)
    |> unique_constraint([:user_id, :course_id], name: :certificates_unique_course_scope)
    |> check_constraint(:type, name: :certificates_type_must_be_valid)
    |> check_constraint(:module_id, name: :certificates_scope_must_match_type)
  end

  defp validate_scope(changeset) do
    case get_field(changeset, :type) do
      :module -> validate_required(changeset, [:module_id])
      :course -> put_change(changeset, :module_id, nil)
      _ -> changeset
    end
  end
end
