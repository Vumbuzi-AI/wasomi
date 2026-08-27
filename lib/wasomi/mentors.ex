defmodule Wasomi.Mentors do
  @moduledoc """
  The Mentors context.
  """

  import Ecto.Query, warn: false
  alias Wasomi.Mentors.Mentor
  alias Wasomi.Repo

  @doc """
  Returns the list of mentors, ordered for the admin table (newest first),
  optionally filtered by a case-insensitive name/role search.
  """
  def list_mentors(opts \\ []) do
    search = Keyword.get(opts, :search)

    Mentor
    |> order_by([mentor], desc: mentor.inserted_at, desc: mentor.id)
    |> filter_by_search(search)
    |> Repo.all()
  end

  defp filter_by_search(query, search) when search in [nil, ""], do: query

  defp filter_by_search(query, search) do
    pattern = "%#{search}%"
    where(query, [mentor], ilike(mentor.name, ^pattern) or ilike(mentor.role, ^pattern))
  end

  @doc """
  Returns active mentors in their public display order, for the homepage.
  """
  def list_active_mentors do
    Mentor
    |> where([mentor], mentor.is_active == true)
    |> order_by([mentor], asc: mentor.position, asc: mentor.id)
    |> Repo.all()
  end

  @doc """
  Counts all mentors, for the admin stat cards.
  """
  def count_mentors, do: Repo.aggregate(Mentor, :count)

  @doc """
  Gets a single mentor.

  Raises `Ecto.NoResultsError` if the Mentor does not exist.
  """
  def get_mentor!(id), do: Repo.get!(Mentor, id)

  @doc """
  Creates a mentor.
  """
  def create_mentor(attrs \\ %{}) do
    attrs = put_default_position(attrs)

    %Mentor{}
    |> Mentor.changeset(attrs)
    |> Repo.insert()
  end

  defp put_default_position(attrs) do
    attrs = Map.new(attrs)
    position_key = if Map.has_key?(attrs, "name"), do: "position", else: :position

    if blank?(Map.get(attrs, position_key)) do
      Map.put(attrs, position_key, next_mentor_position())
    else
      attrs
    end
  end

  defp next_mentor_position do
    (Repo.aggregate(Mentor, :max, :position) || 0) + 1
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  @doc """
  Updates a mentor.
  """
  def update_mentor(%Mentor{} = mentor, attrs) do
    mentor
    |> Mentor.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mentor.
  """
  def delete_mentor(%Mentor{} = mentor) do
    Repo.delete(mentor)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking mentor changes.
  """
  def change_mentor(%Mentor{} = mentor, attrs \\ %{}) do
    Mentor.changeset(mentor, attrs)
  end
end
