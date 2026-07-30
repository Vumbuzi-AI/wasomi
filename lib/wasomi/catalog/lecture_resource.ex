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
    |> validate_number(:byte_size, greater_than: 0)
    |> validate_number(:position, greater_than: 0)
    |> validate_resource_target()
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
        changeset

      kind == :link ->
        add_error(changeset, :url, "must be a valid http or https URL")

      true ->
        add_error(changeset, :storage_key, "is required for uploaded resources")
    end
  end

  defp valid_url?(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_), do: false
end
