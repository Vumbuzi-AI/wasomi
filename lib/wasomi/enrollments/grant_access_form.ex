defmodule Wasomi.Enrollments.GrantAccessForm do
  @moduledoc """
  Non-persisted form used by the admin "Grant access" modal to validate a
  course selection and reason before `Wasomi.Enrollments.grant_access/3` runs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :course_id, :integer
    field :reason, :string
  end

  @doc false
  def changeset(form, attrs) do
    form
    |> cast(attrs, [:course_id, :reason])
    |> validate_required([:course_id, :reason])
    |> validate_length(:reason, min: 10, max: 500)
  end
end
