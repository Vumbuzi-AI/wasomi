defmodule Wasomi.Reviews do
  @moduledoc """
  Course ratings and written reviews.

  A learner is prompted to rate a course once, when they finish its final
  lecture (see `WasomiWeb.CoursePlayerLive`). One review per learner per
  course; re-submitting updates the same row. Reviews are surfaced to admins
  only — there is no public rating display yet.
  """

  import Ecto.Query, warn: false

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Course
  alias Wasomi.Repo
  alias Wasomi.Reviews.CourseReview

  @doc "The learner's review for a course, or nil."
  def get_user_course_review(%User{id: user_id}, %Course{id: course_id}) do
    Repo.get_by(CourseReview, user_id: user_id, course_id: course_id)
  end

  @doc "Whether the learner has already reviewed the course."
  def reviewed?(%User{} = user, %Course{} = course) do
    not is_nil(get_user_course_review(user, course))
  end

  @doc """
  Inserts or updates the learner's review for a course. `attrs` carries
  `rating` (1..5, required) and an optional `body`.
  """
  def upsert_course_review(%User{id: user_id}, %Course{id: course_id}, attrs) do
    (get_user_course_review(%User{id: user_id}, %Course{id: course_id}) || %CourseReview{})
    |> CourseReview.changeset(
      Map.merge(normalize_attrs(attrs), %{"user_id" => user_id, "course_id" => course_id})
    )
    |> Repo.insert_or_update()
  end

  @doc "A blank/prefilled changeset for the review form."
  def change_course_review(%CourseReview{} = review \\ %CourseReview{}, attrs \\ %{}) do
    CourseReview.changeset(review, normalize_attrs(attrs))
  end

  @doc "Count and average rating for a course, average rounded to one decimal."
  def course_review_summary(course_id) do
    query =
      from r in CourseReview,
        where: r.course_id == ^course_id,
        select: {count(r.id), avg(r.rating)}

    case Repo.one(query) do
      {0, _} -> %{count: 0, average: nil}
      {count, avg} -> %{count: count, average: Float.round(to_float(avg), 1)}
      _ -> %{count: 0, average: nil}
    end
  end

  @doc "All reviews for a course, newest first, with the learner preloaded."
  def list_course_reviews(course_id) do
    from(r in CourseReview,
      where: r.course_id == ^course_id,
      order_by: [desc: r.inserted_at, desc: r.id],
      preload: [:user]
    )
    |> Repo.all()
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n / 1
  defp to_float(_), do: 0.0
end
