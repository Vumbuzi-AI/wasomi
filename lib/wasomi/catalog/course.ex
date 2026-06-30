defmodule Wasomi.Catalog.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :position, :integer, default: 1
    field :status, Ecto.Enum, values: [:draft, :published], default: :draft
    field :description, :string
    field :title, :string
    field :currency, :string, default: "KES"
    field :slug, :string
    field :subtitle, :string
    field :thumbnail_key, :string
    field :price_minor, :integer

    has_many :modules, Wasomi.Catalog.CourseModule,
      foreign_key: :course_id,
      preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(course, attrs) do
    course
    |> cast(attrs, [
      :slug,
      :title,
      :subtitle,
      :description,
      :thumbnail_key,
      :price_minor,
      :currency,
      :status,
      :position
    ])
    |> validate_required([
      :slug,
      :title,
      :subtitle,
      :description,
      :thumbnail_key,
      :price_minor,
      :currency,
      :status,
      :position
    ])
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:currency, &String.upcase/1)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must contain lowercase letters, numbers, and hyphens only"
    )
    |> validate_length(:title, min: 3, max: 160)
    |> validate_length(:subtitle, max: 240)
    |> validate_number(:price_minor, greater_than_or_equal_to: 0)
    |> validate_number(:position, greater_than: 0)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/, message: "must be a 3-letter currency code")
    |> unique_constraint(:slug)
    |> check_constraint(:price_minor, name: :courses_price_must_be_non_negative)
    |> check_constraint(:position, name: :courses_position_must_be_positive)
    |> check_constraint(:status, name: :courses_status_must_be_valid)
  end

  defp normalize_slug(slug) when is_binary(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp normalize_slug(slug), do: slug
end
