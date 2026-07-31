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
  Checks whether `course` is ready to publish. Expects modules and lectures
  to already be preloaded (see `Wasomi.Catalog.get_course_with_outline!/1`).

  Returns `:ok`, or `{:error, issues}` where `issues` is an ordered list of
  human-readable strings describing exactly what's missing — enough to
  render as a checklist, not just a single generic error.
  """
  def check(%Course{} = course) do
    modules = course.modules || []
    lectures = Enum.flat_map(modules, & &1.lectures)

    issues =
      []
      |> add_issue(modules == [], "Add at least one module.")
      |> add_issue(modules != [] and lectures == [], "Add at least one lecture.")
      |> add_issue(
        lectures != [] and Enum.any?(lectures, &missing_video?/1),
        "Every lecture needs a video attached."
      )
      |> add_issue(is_nil(course.price_minor), "Set a course price.")
      |> add_issue(blank?(course.thumbnail_key), "Attach a course thumbnail.")

    case Enum.reverse(issues) do
      [] -> :ok
      issues -> {:error, issues}
    end
  end

  defp missing_video?(lecture), do: blank?(lecture.video_asset_id)

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp add_issue(issues, true, message), do: [message | issues]
  defp add_issue(issues, false, _message), do: issues
end
