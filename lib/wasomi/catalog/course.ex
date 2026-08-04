defmodule Wasomi.Catalog.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :position, :integer, default: 1
    field :status, Ecto.Enum, values: [:draft, :in_review, :published], default: :draft
    field :description, :string
    field :title, :string
    field :currency, :string, default: "KES"
    field :slug, :string
    field :subtitle, :string
    field :thumbnail_key, :string
    field :price_minor, :integer

    field :certificate_enabled, :boolean, default: true
    field :certificate_issuer_name, :string
    field :certificate_signatory_name, :string
    field :certificate_signatory_title, :string
    field :certificate_signature_key, :string

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
      :price_minor,
      :currency,
      :status,
      :position
    ])
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:currency, &String.upcase/1)
    |> update_change(:title, &trim/1)
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

  @doc false
  def certificate_changeset(course, attrs) do
    course
    |> cast(attrs, [
      :certificate_enabled,
      :certificate_issuer_name,
      :certificate_signatory_name,
      :certificate_signatory_title,
      :certificate_signature_key
    ])
    |> then(fn changeset ->
      if get_field(changeset, :certificate_enabled) do
        validate_required(changeset, [
          :certificate_issuer_name,
          :certificate_signatory_name,
          :certificate_signatory_title
        ])
      else
        changeset
      end
    end)
    |> validate_change(:certificate_signature_key, fn field, value ->
      if valid_signature_url?(value) do
        []
      else
        [{field, "must be a valid http(s) URL"}]
      end
    end)
  end

  defp valid_signature_url?(nil), do: true

  defp valid_signature_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        trusted_signature_host?(host)

      _ ->
        false
    end
  end

  defp valid_signature_url?(_value), do: false

  # The only legitimate source for this field is the public_url our own R2
  # upload flow returns — restricting the host closes off using this
  # devtools-editable field to make the server-side PDF renderer (headless
  # Chrome) fetch arbitrary hosts (SSRF). Falls back to allowing any http(s)
  # host when R2 isn't configured (e.g. local dev), matching the previous
  # scheme-only check rather than rejecting every signature URL.
  defp trusted_signature_host?(host) do
    case Application.get_env(:wasomi, :r2_public_url) do
      base when is_binary(base) and base != "" ->
        case URI.parse(base) do
          %URI{host: trusted_host} when is_binary(trusted_host) -> host == trusted_host
          _ -> false
        end

      _ ->
        true
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp normalize_slug(slug) when is_binary(slug) do
    slug
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp normalize_slug(slug), do: slug
end
