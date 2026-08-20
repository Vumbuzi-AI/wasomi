defmodule Wasomi.Mentors.Mentor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mentors" do
    field :name, :string
    field :role, :string
    field :photo_key, :string
    field :twitter_url, :string
    field :facebook_url, :string
    field :linkedin_url, :string
    field :position, :integer, default: 1
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(mentor, attrs) do
    mentor
    |> cast(attrs, [
      :name,
      :role,
      :photo_key,
      :twitter_url,
      :facebook_url,
      :linkedin_url,
      :position,
      :is_active
    ])
    |> validate_required([:name, :role, :position])
    |> update_change(:name, &trim/1)
    |> update_change(:role, &trim/1)
    |> validate_length(:name, min: 2, max: 120)
    |> validate_length(:role, min: 2, max: 120)
    |> validate_number(:position, greater_than: 0)
    |> validate_url(:twitter_url)
    |> validate_url(:facebook_url)
    |> validate_url(:linkedin_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if valid_url?(value), do: [], else: [{field, "must be a valid http(s) URL"}]
    end)
  end

  defp valid_url?(nil), do: true
  defp valid_url?(""), do: true

  defp valid_url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp valid_url?(_value), do: false

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
