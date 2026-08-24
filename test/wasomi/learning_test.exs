defmodule Wasomi.LearningTest do
  use Wasomi.DataCase

  alias Wasomi.Assessments
  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress

  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
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

  describe "resource reading marks" do
    setup do
      user = user_fixture()
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)
      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

      reading_lecture =
        lecture_fixture(
          module_id: module.id,
          position: 1,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      %{user: user, course: course, module: module, reading_lecture: reading_lecture}
    end

    test "reading every PDF completes a reading-only lecture", context do
      first = lecture_resource_fixture(lecture_id: context.reading_lecture.id, position: 1)
      second = lecture_resource_fixture(lecture_id: context.reading_lecture.id, position: 2)

      assert {:ok, []} = Learning.mark_resource_read(context.user, first)

      # One still outstanding, so the lecture is untouched.
      assert is_nil(Learning.get_lecture_progress(context.user, context.reading_lecture))

      assert {:ok, events} = Learning.mark_resource_read(context.user, second)
      assert Enum.any?(events, &match?({:lecture_completed, _}, &1))

      assert %{status: :completed} =
               Learning.get_lecture_progress(context.user, context.reading_lecture)
    end

    test "marking the same resource read twice is a no-op, not an error", context do
      resource = lecture_resource_fixture(lecture_id: context.reading_lecture.id)

      assert {:ok, _events} = Learning.mark_resource_read(context.user, resource)
      assert {:ok, _events} = Learning.mark_resource_read(context.user, resource)

      assert Learning.read_resource_ids_for_course(context.user, context.course) ==
               MapSet.new([resource.id])
    end

    test "reading the handouts does not complete a lecture that has a video", context do
      video_lecture =
        lecture_fixture(module_id: context.module.id, position: 2, duration_seconds: 100)

      resource = lecture_resource_fixture(lecture_id: video_lecture.id)

      assert {:ok, []} = Learning.mark_resource_read(context.user, resource)
      assert is_nil(Learning.get_lecture_progress(context.user, video_lecture))
    end

    test "un-marking removes the read mark but keeps the lecture completed", context do
      resource = lecture_resource_fixture(lecture_id: context.reading_lecture.id)

      assert {:ok, _events} = Learning.mark_resource_read(context.user, resource)
      assert :ok = Learning.unmark_resource_read(context.user, resource)

      assert Learning.read_resource_ids_for_course(context.user, context.course) ==
               MapSet.new()

      assert %{status: :completed} =
               Learning.get_lecture_progress(context.user, context.reading_lecture)
    end

    test "a learner without an active enrollment cannot mark a resource read", context do
      outsider = user_fixture()
      resource = lecture_resource_fixture(lecture_id: context.reading_lecture.id)

      assert {:error, :forbidden} = Learning.mark_resource_read(outsider, resource)
    end

    test "read_resource_ids_for_course/2 is scoped to the course asked about", context do
      resource = lecture_resource_fixture(lecture_id: context.reading_lecture.id)
      assert {:ok, _events} = Learning.mark_resource_read(context.user, resource)

      other_course = course_fixture(status: :published)

      assert Learning.read_resource_ids_for_course(context.user, other_course) == MapSet.new()
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

    test "mark_complete/2 completes a video-less lecture immediately, with nothing to watch" do
      user = user_fixture()
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)

      lecture =
        lecture_fixture(
          module_id: module.id,
          position: 1,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

      assert {:ok, progress, _events} = Learning.mark_complete(user, lecture)
      assert progress.status == :completed
      assert progress.last_position_seconds == 0
    end

    test "record_progress/3 rejects a video-progress event forged for a video-less lecture" do
      user = user_fixture()
      course = course_fixture(status: :published)
      module = course_module_fixture(course_id: course.id, position: 1)

      lecture =
        lecture_fixture(
          module_id: module.id,
          position: 1,
          duration_seconds: nil,
          video_asset_id: nil,
          video_provider: nil
        )

      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

      assert {:error, :no_video} = Learning.record_progress(user, lecture, 30)
      refute Learning.get_lecture_progress(user, lecture)
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

  describe "completion_percent_by_user/1" do
    test "batch-computes each user's percentage in one query, absent means 0%" do
      course = course_fixture(status: :published)
      course_module = course_module_fixture(course_id: course.id, position: 1)
      first = lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)
      lecture_fixture(module_id: course_module.id, position: 2, duration_seconds: 100)

      halfway = user_fixture()
      not_started = user_fixture()
      enrollment_fixture(user_id: halfway.id, course_id: course.id, status: :active)
      enrollment_fixture(user_id: not_started.id, course_id: course.id, status: :active)

      complete_lecture_via_progress!(halfway, first)

      course = Wasomi.Catalog.get_course_by_slug!(course.slug)
      percentages = Learning.completion_percent_by_user(course)

      assert percentages[halfway.id] == 50
      refute Map.has_key?(percentages, not_started.id)
    end
  end

  describe "count_incomplete_enrollees/1" do
    test "is zero when the course has no active enrollees" do
      course = course_fixture(status: :published)
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)

      assert Learning.count_incomplete_enrollees(course) == 0
    end

    test "is zero when every active enrollee has completed the course" do
      user = user_fixture()
      course = course_fixture(status: :published)
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)
      enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

      complete_lecture_via_progress!(user, lecture)

      assert Learning.count_incomplete_enrollees(course) == 0
    end

    test "counts active enrollees who haven't finished, ignoring pending enrollments" do
      finished = user_fixture()
      in_progress = user_fixture()
      still_pending = user_fixture()

      course = course_fixture(status: :published)
      course_module = course_module_fixture(course_id: course.id, position: 1)
      lecture = lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)

      enrollment_fixture(user_id: finished.id, course_id: course.id, status: :active)
      enrollment_fixture(user_id: in_progress.id, course_id: course.id, status: :active)
      enrollment_fixture(user_id: still_pending.id, course_id: course.id, status: :pending)

      complete_lecture_via_progress!(finished, lecture)

      assert Learning.count_incomplete_enrollees(course) == 1
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

  describe "lecture quiz gating" do
    test "a completed lecture with no lecture quiz unlocks the next lecture (no regression)" do
      %{course: course, first: first, second: second, user: user} = two_lecture_course()

      complete_lecture_via_progress!(user, first)

      assert Learning.lecture_unlocked?(user, course, second)
    end

    test "a completed lecture whose quiz has no published questions yet still unlocks the next lecture" do
      %{course: course, first: first, second: second, user: user} = two_lecture_course()
      lecture_quiz_fixture(lecture: first)

      complete_lecture_via_progress!(user, first)

      assert Learning.lecture_unlocked?(user, course, second)
    end

    test "a completed lecture with a ready quiz blocks the next lecture until attempted" do
      %{course: course, first: first, second: second, user: user} = two_lecture_course()
      published_lecture_quiz(first)

      complete_lecture_via_progress!(user, first)

      refute Learning.lecture_unlocked?(user, course, second)
    end

    test "failing the lecture quiz still blocks the next lecture" do
      %{course: course, first: first, second: second, user: user} = two_lecture_course()
      quiz = published_lecture_quiz(first)
      Assessments.submit_lecture_quiz(user, quiz, %{})

      complete_lecture_via_progress!(user, first)

      refute Learning.lecture_unlocked?(user, course, second)
    end

    test "passing the lecture quiz unlocks the next lecture" do
      %{course: course, first: first, second: second, user: user} = two_lecture_course()
      quiz = published_lecture_quiz(first)
      [question] = Assessments.list_published_lecture_quiz_questions(quiz)
      correct_option = Enum.find(question.question_options, & &1.correct)

      assert {:ok, %{passed: true}} =
               Assessments.submit_lecture_quiz(user, quiz, %{question.id => correct_option.id})

      complete_lecture_via_progress!(user, first)

      assert Learning.lecture_unlocked?(user, course, second)
    end
  end

  defp two_lecture_course do
    course = course_fixture(status: :published)
    course_module = course_module_fixture(course_id: course.id, position: 1)
    first = lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)
    second = lecture_fixture(module_id: course_module.id, position: 2, duration_seconds: 100)
    user = user_fixture()

    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)
    course = Wasomi.Catalog.get_course_by_slug!(course.slug)

    %{course: course, first: first, second: second, user: user}
  end

  defp published_lecture_quiz(lecture) do
    quiz = lecture_quiz_fixture(lecture: lecture)
    generation = lecture_quiz_generation_fixture(lecture_quiz: quiz)

    {:ok, 1} =
      Assessments.create_lecture_quiz_draft_questions_and_mark_ready(generation, [
        draft_question_attrs()
      ])

    Assessments.publish_all_lecture_quiz_drafts(quiz)
    quiz
  end
end

