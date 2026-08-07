defmodule Wasomi.LearningTest do
  use Wasomi.DataCase

  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress

  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures

  describe "lecture progress CRUD" do
    test "unfinished progress does not require completed_at" do
      progress = lecture_progress_fixture(status: :in_progress, last_position_seconds: 12)

      assert progress.status == :in_progress
      assert progress.last_position_seconds == 12
      assert is_nil(progress.completed_at)
    end

    test "completed progress requires completed_at" do
      user = user_fixture()
      lecture = lecture_fixture()

      assert {:error, changeset} =
               Learning.create_lecture_progress(%{
                 user_id: user.id,
                 lecture_id: lecture.id,
                 status: :completed,
                 last_position_seconds: 42
               })

      assert "can't be blank" in errors_on(changeset).completed_at
    end

    test "enforces one progress row per learner and lecture" do
      progress = lecture_progress_fixture()

      assert {:error, changeset} =
               Learning.create_lecture_progress(%{
                 user_id: progress.user_id,
                 lecture_id: progress.lecture_id,
                 status: :in_progress,
                 last_position_seconds: 10
               })

      assert "has already been taken" in errors_on(changeset).user_id
    end
  end

  describe "record_progress/3" do
    setup do
      user = user_fixture()
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)

      lecture =
        lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)

      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

      %{user: user, course: course, module: module, lecture: lecture}
    end

    test "upserts monotonic progress below the completion threshold", context do
      assert {:ok, progress, []} =
               Learning.record_progress(context.user, context.lecture, 15)

      assert progress.status == :in_progress
      assert progress.last_position_seconds == 15
      assert is_nil(progress.completed_at)

      assert {:ok, progress, []} =
               Learning.record_progress(context.user, context.lecture, 5)

      assert progress.last_position_seconds == 15
      assert Repo.aggregate(LectureProgress, :count) == 1
    end

    test "completes at 95 percent and emits lecture/module/course events", context do
      :ok = Learning.subscribe(context.user)
      seed_and_backdate_save!(context.user, context.lecture, 30)

      assert {:ok, progress,
              [
                {:lecture_completed, completed_progress},
                {:module_completed, module},
                {:course_completed, course}
              ]} = Learning.record_progress(context.user, context.lecture, 95)

      assert completed_progress.id == progress.id
      assert module.id == context.module.id
      assert course.id == context.course.id
      assert progress.status == :completed
      assert progress.completed_at

      assert_receive {:lecture_completed, %LectureProgress{id: id}}
      assert id == progress.id
      assert_receive {:module_completed, %{id: module_id}}
      assert module_id == context.module.id
      assert_receive {:course_completed, %{id: course_id}}
      assert course_id == context.course.id
    end

    test "94 percent remains in progress", context do
      seed_and_backdate_save!(context.user, context.lecture, 30)

      assert {:ok, progress, []} =
               Learning.record_progress(context.user, context.lecture, 94)

      assert progress.status == :in_progress
    end

    test "rejects a forged jump-ahead as an anti-cheat backstop for the client-side seek guard",
         context do
      assert {:ok, _progress, []} = Learning.record_progress(context.user, context.lecture, 10)

      # +85s claimed with ~0 real time elapsed — a forged jump.
      assert {:ok, progress, []} = Learning.record_progress(context.user, context.lecture, 95)

      assert progress.status == :in_progress
      # Clamped to last (10) + floor allowance (20), not the raw 95.
      assert progress.last_position_seconds == 30
    end

    test "a large jump is accepted once enough real time has plausibly elapsed", context do
      assert {:ok, progress, []} = Learning.record_progress(context.user, context.lecture, 10)

      Repo.update!(
        Ecto.Changeset.change(progress,
          updated_at:
            DateTime.utc_now() |> DateTime.add(-30, :second) |> DateTime.truncate(:second)
        )
      )

      # +85s over 30s elapsed — within the 4x allowance.
      assert {:ok, progress, [_lecture, _module, _course]} =
               Learning.record_progress(context.user, context.lecture, 95)

      assert progress.status == :completed
      assert progress.last_position_seconds == 95
    end

    test "rejects a forged jump-ahead on the very first save for a lecture", context do
      # No prior row — the simplest version of the exploit.
      assert {:ok, progress, []} = Learning.record_progress(context.user, context.lecture, 95)

      assert progress.status == :in_progress
      assert progress.last_position_seconds == 20
    end

    test "mark_complete/2 is a no-op once the lecture is already completed", context do
      :ok = Learning.subscribe(context.user)
      seed_and_backdate_save!(context.user, context.lecture, 30)

      assert {:ok, first, [_lecture, _module, _course]} =
               Learning.record_progress(context.user, context.lecture, 96)

      assert_receive {:lecture_completed, _}
      assert_receive {:module_completed, _}
      assert_receive {:course_completed, _}

      assert {:ok, second, []} = Learning.mark_complete(context.user, context.lecture)
      assert first.completed_at == second.completed_at
      refute_receive {:lecture_completed, _}
      refute_receive {:module_completed, _}
      refute_receive {:course_completed, _}
    end

    test "mark_complete/2 rejects a lecture that hasn't been watched enough", context do
      assert {:error, :insufficient_watch_time} =
               Learning.mark_complete(context.user, context.lecture)

      {:ok, _progress, []} = Learning.record_progress(context.user, context.lecture, 40)

      assert {:error, :insufficient_watch_time} =
               Learning.mark_complete(context.user, context.lecture)

      refute Learning.get_lecture_progress(context.user, context.lecture).status == :completed
    end

    test "rejects progress without an active enrollment", context do
      outsider = user_fixture()

      assert {:error, :forbidden} =
               Learning.record_progress(outsider, context.lecture, 95)

      refute Learning.get_lecture_progress(outsider, context.lecture)
    end
  end

  describe "completion roll-up and sequential unlocks" do
    test "a module and course complete only after all scoped lectures complete" do
      user = user_fixture()
      course = course_fixture(status: :published)
      first_module = course_module_fixture(course_id: course.id, position: 1)
      second_module = course_module_fixture(course_id: course.id, position: 2)

      first =
        lecture_fixture(module_id: first_module.id, position: 1, duration_seconds: 100)

      second =
        lecture_fixture(module_id: first_module.id, position: 2, duration_seconds: 100)

      third =
        lecture_fixture(module_id: second_module.id, position: 1, duration_seconds: 100)

      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)
      course = Wasomi.Catalog.get_course_by_slug!(course.slug)

      assert Learning.next_lecture(user, course).id == first.id
      assert Learning.lecture_unlocked?(user, course, first)
      refute Learning.lecture_unlocked?(user, course, second)

      assert {:ok, _, [{:lecture_completed, _}]} =
               complete_lecture_via_progress!(user, first)

      assert Learning.lecture_unlocked?(user, course, second)
      refute Learning.lecture_unlocked?(user, course, third)

      assert {:ok, _,
              [
                {:lecture_completed, _},
                {:module_completed, completed_module}
              ]} = complete_lecture_via_progress!(user, second)

      assert completed_module.id == first_module.id
      assert Learning.lecture_unlocked?(user, course, third)

      assert {:ok, _,
              [
                {:lecture_completed, _},
                {:module_completed, completed_module},
                {:course_completed, completed_course}
              ]} = complete_lecture_via_progress!(user, third)

      assert completed_module.id == second_module.id
      assert completed_course.id == course.id

      assert %{completed: 3, total: 3, percent: 100, complete?: true} =
               Learning.course_progress(user, course)
    end
  end

  # Seeds a small first save and backdates it, so a later big jump reads as
  # plausible instead of getting clamped.
  defp seed_and_backdate_save!(user, lecture, seconds_ago) do
    {:ok, _progress, []} = Learning.record_progress(user, lecture, 1)

    Repo.update!(
      Ecto.Changeset.change(
        Learning.get_lecture_progress(user, lecture),
        updated_at:
          DateTime.utc_now() |> DateTime.add(-seconds_ago, :second) |> DateTime.truncate(:second)
      )
    )
  end
end
