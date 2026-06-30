defmodule Wasomi.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Catalog` context.
  """

  @doc """
  Generate a unique course slug.
  """
  def unique_course_slug, do: "course-#{System.unique_integer([:positive])}"

  @doc """
  Generate a course.
  """
  def course_fixture(attrs \\ %{}) do
    {:ok, course} =
      attrs
      |> Enum.into(%{
        currency: "KES",
        description: "some description",
        position: 42,
        price_minor: 42,
        slug: unique_course_slug(),
        status: :draft,
        subtitle: "some subtitle",
        thumbnail_key: "some thumbnail_key",
        title: "some title"
      })
      |> Wasomi.Catalog.create_course()

    course
  end

  @doc """
  Generate a course_module.
  """
  def course_module_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    course_id = Map.get_lazy(attrs, :course_id, fn -> course_fixture().id end)

    {:ok, course_module} =
      attrs
      |> Map.put(:course_id, course_id)
      |> Enum.into(%{
        description: "some description",
        position: 42,
        title: "some title"
      })
      |> Wasomi.Catalog.create_course_module()

    course_module
  end

  @doc """
  Generate a lecture.
  """
  def lecture_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    module_id = Map.get_lazy(attrs, :module_id, fn -> course_module_fixture().id end)

    {:ok, lecture} =
      attrs
      |> Map.put(:module_id, module_id)
      |> Enum.into(%{
        description: "some description",
        duration_seconds: 42,
        position: 42,
        title: "some title",
        video_asset_id: "some video_asset_id",
        video_provider: :mux
      })
      |> Wasomi.Catalog.create_lecture()

    lecture
  end
end
