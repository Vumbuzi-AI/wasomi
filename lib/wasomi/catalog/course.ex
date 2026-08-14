defmodule Wasomi.Catalog.Course do
  use Ecto.Schema
  import Ecto.Changeset

  schema "courses" do
    field :position, :integer, default: 1
    field :status, Ecto.Enum, values: [:draft, :published, :archived], default: :draft
    field :description, :string
    field :title, :string
    field :currency, :string, default: "KES"
    field :slug, :string
    field :thumbnail_key, :string
    field :price_minor, :integer
    field :is_free, :boolean, default: false

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
      :description,
      :thumbnail_key,
      :price_minor,
      :status,
      :position,
      :is_free
    ])
    |> validate_required([
      :slug,
      :title,
      :description,
      :status,
      :position
    ])
    |> validate_price()
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:title, &trim/1)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must contain lowercase letters, numbers, and hyphens only"
    )
    |> validate_length(:title, min: 3, max: 160)
    |> validate_number(:position, greater_than: 0)
    |> unique_constraint(:slug)
    |> check_constraint(:price_minor, name: :courses_price_must_be_non_negative)
    |> check_constraint(:position, name: :courses_position_must_be_positive)
    |> check_constraint(:status, name: :courses_status_must_be_valid)
  end

  defp validate_price(changeset) do
    if get_field(changeset, :is_free) do
      put_change(changeset, :price_minor, nil)
    else
      changeset
      |> validate_required([:price_minor])
      |> validate_number(:price_minor, greater_than_or_equal_to: 0)
    end
  end

  @doc """
  The dedicated changeset for the `:published` transition.

  A second line of defense alongside `PublishGuard`, independent of it, so
  a future direct `Repo.update` bypassing `Catalog.publish_course/1` still
  can't produce a published-but-empty course. Expects `course.modules`
  (and each module's `.lectures`) already preloaded.
  """
  def publish_changeset(course) do
    course
    |> change(status: :published)
    |> check_constraint(:status, name: :courses_status_must_be_valid)
    |> validate_publishable_content()
  end

  defp validate_publishable_content(changeset) do
    modules = changeset.data.modules || []

    cond do
      modules == [] ->
        add_error(changeset, :status, "cannot publish a course with no modules")

      Enum.any?(modules, &(&1.lectures == [])) ->
        add_error(
          changeset,
          :status,
          "cannot publish a course with a module that has no lectures"
        )

      true ->
        changeset
    end
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
  # Chrome) fetch arbitrary hosts (SSRF). Fails closed when R2 isn't
  # configured, rather than allowing any host: a legitimate signature_key can
  # never be populated without R2 configured anyway (the upload flow itself
  # requires it), so this costs no real capability — only an unconfigured
  # environment "permissively" allowing every host would be a real gap.
  defp trusted_signature_host?(host) do
    case Application.get_env(:wasomi, :r2_public_url) do
      base when is_binary(base) and base != "" ->
        case URI.parse(base) do
          %URI{host: trusted_host} when is_binary(trusted_host) -> host == trusted_host
          _ -> false
        end

      _ ->
        false
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
