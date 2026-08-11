defmodule Wasomi.CatalogFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Catalog` context.
  """
  alias Wasomi.Catalog.{LectureQuestion, LectureResource}

  @doc """
  Generate a unique course slug.
  """
  def unique_course_slug, do: "course-#{System.unique_integer([:positive])}"

  @certificate_keys [
    :certificate_enabled,
    :certificate_issuer_name,
    :certificate_signatory_name,
    :certificate_signatory_title,
    :certificate_signature_key
  ]

  @doc """
  Generate a course.

  `Course.changeset/2` doesn't cast certificate fields (they go through the
  dedicated `certificate_changeset/2`), so any `certificate_*` keys in
  `attrs` are applied as a second step. Defaults to `certificate_enabled:
  false` — publishing is the common case in tests, and `certificate_enabled`
  defaults to `true` on the schema with no signatory details, which would
  otherwise fail every publish-flow test's `PublishGuard` check.
  """
  def course_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    {certificate_attrs, course_attrs} = Map.split(attrs, @certificate_keys)

    {:ok, course} =
      course_attrs
      |> Enum.into(%{
        currency: "KES",
        description: "some description",
        position: 42,
        price_minor: 42,
        slug: unique_course_slug(),
        status: :draft,
        thumbnail_key: "some thumbnail_key",
        title: "some title"
      })
      |> Wasomi.Catalog.create_course()

    {:ok, course} =
      Wasomi.Catalog.update_course_certificate(
        course,
        Enum.into(certificate_attrs, %{certificate_enabled: false})
      )

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
        title: "some title #{System.unique_integer([:positive])}"
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
        title: "some title #{System.unique_integer([:positive])}",
        video_asset_id: "some video_asset_id",
        video_provider: :mux
      })
      |> Wasomi.Catalog.create_lecture()

    lecture
  end

  def lecture_resource_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    lecture_id = Map.get_lazy(attrs, :lecture_id, fn -> lecture_fixture().id end)

    resource_attrs =
      attrs
      |> Map.put(:lecture_id, lecture_id)
      |> Enum.into(%{
        byte_size: 100,
        content_type: "application/pdf",
        kind: :document,
        name: "Notes",
        position: 1,
        storage_key: "lectures/notes.pdf"
      })

    {:ok, resource} =
      %LectureResource{}
      |> LectureResource.changeset(resource_attrs)
      |> Wasomi.Repo.insert()

    resource
  end

  def lecture_question_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    lecture_id = Map.get_lazy(attrs, :lecture_id, fn -> lecture_fixture().id end)

    question_attrs =
      attrs
      |> Map.put(:lecture_id, lecture_id)
      |> Enum.into(%{
        answer: "The answer",
        position: 1,
        question: "What is this?"
      })

    {:ok, question} =
      %LectureQuestion{}
      |> LectureQuestion.changeset(question_attrs)
      |> Wasomi.Repo.insert()

    question
  end
end
