defmodule Wasomi.Catalog.PublishGuard do
  @moduledoc """
  The pre-publish checklist a course must pass before it can go live in the
  public catalog.

  `Wasomi.Catalog.publish_course/1` is the only path that flips a course's
  status to `:published` — it always re-fetches the course with its current
  outline and runs this guard first, so publishing a course from a stale
  in-memory struct (e.g. a form that hasn't seen a module just added on
  another tab) can never skip a check. The status `<select>` on the course
  edit form does not offer `:published` for the same reason: reaching
  `:published` by any path other than a passing guard would defeat the
  point of having one.
  """

  alias Wasomi.Catalog.Course

  @doc """
  Checks whether `course` is ready to publish. Expects modules, lectures, and
  each module's quiz to already be preloaded (see
  `Wasomi.Catalog.get_course_with_outline!/1`).

  Returns `:ok`, or `{:error, issues}` where `issues` is an ordered list of
  human-readable strings describing exactly what's missing — enough to
  render as a checklist, not just a single generic error.
  """
  def check(%Course{} = course) do
    issues = course |> stages() |> Enum.flat_map(& &1.reasons)

    case issues do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  @doc """
  The same checks as `check/1`, broken out stage by stage instead of
  collapsed into a single pass/fail — for the admin UI to render as a full
  checklist (what's already ready, not just what's missing). Each stage
  always appears, whichever way it resolves, so an admin can see the whole
  picture rather than only ever seeing failures.

  A stage's `:status` is one of:
    * `:passed` — actually checked, and satisfied.
    * `:failed` — checked, and not satisfied (see `:reasons`).
    * `:not_applicable` — nothing to check yet (e.g. no lectures exist at
      all, so "every lecture has a video" is vacuously true). Deliberately
      distinct from `:passed` — a checkmark would read as "verified good"
      when really nothing was there to verify, which is misleading.
  """
  def checklist(%Course{} = course) do
    stages(course)
  end

  defp stages(course) do
    modules = course.modules || []
    lectures = Enum.flat_map(modules, & &1.lectures)

    [
      %{
        stage: "Curriculum",
        status: status(modules != [] and Enum.all?(modules, &(&1.lectures != []))),
        reasons:
          []
          |> add_issue(modules == [], "Add at least one module.")
          |> add_issue(modules != [] and lectures == [], "Add at least one lecture.")
          |> add_issue(
            lectures != [] and Enum.any?(modules, &(&1.lectures == [])),
            "Every module needs at least one lecture."
          )
          |> Enum.reverse()
      },
      %{
        stage: "Lecture content",
        status:
          cond do
            lectures == [] -> :not_applicable
            Enum.any?(lectures, &missing_video?/1) -> :failed
            true -> :passed
          end,
        reasons:
          []
          |> add_issue(
            lectures != [] and Enum.any?(lectures, &missing_video?/1),
            "Every lecture needs a video attached."
          )
          |> Enum.reverse()
      },
      %{
        stage: "Pricing",
        status: status(not is_nil(course.price_minor)),
        reasons:
          [] |> add_issue(is_nil(course.price_minor), "Set a course price.") |> Enum.reverse()
      },
      %{
        stage: "Thumbnail",
        status: status(not blank?(course.thumbnail_key)),
        reasons:
          []
          |> add_issue(blank?(course.thumbnail_key), "Attach a course thumbnail.")
          |> Enum.reverse()
      },
      %{
        stage: "Quizzes",
        status:
          cond do
            Enum.all?(modules, &is_nil(&1.quiz)) -> :not_applicable
            Enum.any?(modules, &unpublished_quiz?/1) -> :failed
            true -> :passed
          end,
        reasons:
          []
          |> add_issue(
            Enum.any?(modules, &unpublished_quiz?/1),
            "Publish every module's quiz before publishing the course."
          )
          |> Enum.reverse()
      },
      %{
        stage: "Certificate details",
        status:
          cond do
            not course.certificate_enabled -> :not_applicable
            missing_signatory_details?(course) -> :failed
            true -> :passed
          end,
        reasons:
          []
          |> add_issue(
            course.certificate_enabled and missing_signatory_details?(course),
            "Add certificate issuer and signatory details, or disable certificates for this course."
          )
          |> Enum.reverse()
      }
    ]
  end

  defp status(true), do: :passed
  defp status(false), do: :failed

  defp missing_video?(lecture), do: blank?(lecture.video_asset_id)

  defp unpublished_quiz?(%{quiz: %{active: false}}), do: true
  defp unpublished_quiz?(_module), do: false

  defp missing_signatory_details?(course) do
    blank?(course.certificate_issuer_name) or
      blank?(course.certificate_signatory_name) or
      blank?(course.certificate_signatory_title)
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp add_issue(issues, true, message), do: [message | issues]
  defp add_issue(issues, false, _message), do: issues
end
