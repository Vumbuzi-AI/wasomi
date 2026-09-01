defmodule Wasomi.ReviewsTest do
  use Wasomi.DataCase, async: true

  alias Wasomi.Reviews

  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

  setup do
    %{user: user_fixture(), course: course_fixture()}
  end

  describe "upsert_course_review/3" do
    test "inserts a new review", %{user: user, course: course} do
      assert {:ok, review} =
               Reviews.upsert_course_review(user, course, %{"rating" => "4", "body" => " Great "})

      assert review.rating == 4
      assert review.body == "Great"
      assert review.user_id == user.id
      assert review.course_id == course.id
    end

    test "updates the same row on a second submission", %{user: user, course: course} do
      {:ok, first} = Reviews.upsert_course_review(user, course, %{"rating" => 3})

      {:ok, second} =
        Reviews.upsert_course_review(user, course, %{"rating" => 5, "body" => "Better"})

      assert first.id == second.id
      assert second.rating == 5
      assert second.body == "Better"
      assert [_only] = Reviews.list_course_reviews(course.id)
    end

    test "blank body is stored as nil", %{user: user, course: course} do
      {:ok, review} =
        Reviews.upsert_course_review(user, course, %{"rating" => 4, "body" => "   "})

      assert review.body == nil
    end

    test "rejects a rating outside 1..5", %{user: user, course: course} do
      assert {:error, changeset} = Reviews.upsert_course_review(user, course, %{"rating" => 6})
      assert "must be between 1 and 5 stars" in errors_on(changeset).rating
    end

    test "rejects a missing rating", %{user: user, course: course} do
      assert {:error, changeset} = Reviews.upsert_course_review(user, course, %{"body" => "x"})
      assert "can't be blank" in errors_on(changeset).rating
    end
  end

  describe "reads" do
    test "get_user_course_review/2 and reviewed?/2", %{user: user, course: course} do
      refute Reviews.reviewed?(user, course)
      assert Reviews.get_user_course_review(user, course) == nil

      {:ok, _} = Reviews.upsert_course_review(user, course, %{"rating" => 4})

      assert Reviews.reviewed?(user, course)
      assert %{rating: 4} = Reviews.get_user_course_review(user, course)
    end

    test "course_review_summary/1 averages ratings", %{course: course} do
      assert Reviews.course_review_summary(course.id) == %{count: 0, average: nil}

      {:ok, _} = Reviews.upsert_course_review(user_fixture(), course, %{"rating" => 5})
      {:ok, _} = Reviews.upsert_course_review(user_fixture(), course, %{"rating" => 2})

      assert Reviews.course_review_summary(course.id) == %{count: 2, average: 3.5}
    end

    test "list_course_reviews/1 returns newest first with the user preloaded", %{course: course} do
      {:ok, _} = Reviews.upsert_course_review(user_fixture(), course, %{"rating" => 3})
      {:ok, latest} = Reviews.upsert_course_review(user_fixture(), course, %{"rating" => 4})

      assert [first, _] = Reviews.list_course_reviews(course.id)
      assert first.id == latest.id
      assert %Wasomi.Accounts.User{} = first.user
    end
  end
end
