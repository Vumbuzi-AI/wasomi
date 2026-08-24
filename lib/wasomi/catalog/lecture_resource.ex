defmodule Wasomi.Catalog.LectureResource do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lecture_resources" do
    field :kind, Ecto.Enum, values: [:document, :video, :link]
    field :name, :string
    field :storage_key, :string
    field :url, :string
    field :content_type, :string
    field :byte_size, :integer
    field :position, :integer
    belongs_to :lecture, Wasomi.Catalog.Lecture

    timestamps(type: :utc_datetime)
  end

  defp validate_byte_size(changeset) do
    if is_nil(get_field(changeset, :byte_size)) do
      changeset
    else
      validate_number(changeset, :byte_size, greater_than: 0)
    end
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [
      :kind,
      :name,
      :storage_key,
      :url,
      :content_type,
      :byte_size,
      :position,
      :lecture_id
    ])
    |> validate_required([:kind, :name, :position, :lecture_id])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_byte_size()
    |> validate_number(:position, greater_than: 0)
    |> validate_resource_target()
    |> validate_document_is_pdf()
    |> assoc_constraint(:lecture)
    |> unique_constraint([:lecture_id, :position],
      name: :lecture_resources_lecture_id_position_index
    )
  end

  defp validate_resource_target(changeset) do
    kind = get_field(changeset, :kind)
    storage_key = get_field(changeset, :storage_key)
    url = get_field(changeset, :url)

    cond do
      kind == :link and valid_url?(url) ->
        changeset

      kind in [:document, :video] and is_binary(storage_key) and storage_key != "" ->
        if is_integer(get_field(changeset, :byte_size)) and get_field(changeset, :byte_size) > 0 do
          changeset
        else
          add_error(changeset, :byte_size, "must be greater than 0 for uploaded resources")
        end

      kind == :link ->
        add_error(changeset, :url, "must be a valid http or https URL")

      true ->
        add_error(changeset, :storage_key, "is required for uploaded resources")
    end
  end

  def valid_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  def valid_url?(_), do: false

  # Uploaded lecture resources are PDF only. The learner's reader renders them
  # inline and `Wasomi.Assessments.LectureResourceReader` extracts their text to
  # drive study guides and generated quizzes — neither works for an image, a
  # slide deck or an archive. Enforced here as well as in the uploader's
  # `accept:` list so a resource row can't be written past the UI.
  defp validate_document_is_pdf(changeset) do
    if get_field(changeset, :kind) == :document and not pdf?(changeset) do
      add_error(changeset, :content_type, "must be a PDF — lecture resources only accept PDFs")
    else
      changeset
    end
  end

  defp pdf?(changeset) do
    content_type = get_field(changeset, :content_type)
    name = get_field(changeset, :name) || ""
    pdf_name? = String.downcase(Path.extname(name)) == ".pdf"

    case content_type do
      "application/pdf" -> true
      # The browser doesn't always send a type; fall back to the filename,
      # which is the same leniency the uploader's own check applies.
      type when type in [nil, "", "application/octet-stream"] -> pdf_name?
      _ -> false
    end
  end
end
