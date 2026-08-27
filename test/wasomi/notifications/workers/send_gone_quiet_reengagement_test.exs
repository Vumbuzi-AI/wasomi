defmodule Wasomi.Notifications.Workers.SendGoneQuietReengagementTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Learning
  alias Wasomi.Learning.LectureProgress
  alias Wasomi.Notifications.Notification
  alias Wasomi.Notifications.Workers.{SendGoneQuietReengagement, SendNeverStartedReengagement}

  test "emails an active enrollment whose progress has gone stale" do
    %{user: user, course: course} = enrolled_with_stale_progress(20)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])

    assert_email_sent(subject: "Pick up right where you left off in \"#{course.title}\"")

    assert Repo.get_by(Notification,
             user_id: user.id,
             course_id: course.id,
             kind: :reengagement_gone_quiet
           )
  end

  test "does not email an enrollment with recent progress" do
    %{user: user, lecture: lecture} = enrolled_with_stale_progress(20)
    # A later position than the stale row's, so this is a real DB write that
    # bumps `updated_at` to now — identical values are a documented Ecto
    # no-op (empty changeset -> no UPDATE issued), which would otherwise
    # leave `updated_at` looking falsely stale.
    Learning.record_progress(user, lecture, 5)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])

    assert_no_email_sent()
  end

  test "never fires alongside the never-started job for the same learner" do
    %{user: user, course: course} = enrolled_with_zero_progress(20)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])
    assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])
    assert_no_email_sent()

    assert Repo.aggregate(
             from(n in Notification, where: n.user_id == ^user.id),
             :count
           ) == 1
  end

  test "processes every eligible enrollment in one run, not just the first" do
    %{user: user_a, course: course_a} = enrolled_with_stale_progress(20)
    %{user: user_b, course: course_b} = enrolled_with_stale_progress(20)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])

    assert_email_sent(subject: "Pick up right where you left off in \"#{course_a.title}\"")
    assert_email_sent(subject: "Pick up right where you left off in \"#{course_b.title}\"")

    assert Repo.get_by(Notification,
             user_id: user_a.id,
             course_id: course_a.id,
             kind: :reengagement_gone_quiet
           )

    assert Repo.get_by(Notification,
             user_id: user_b.id,
             course_id: course_b.id,
             kind: :reengagement_gone_quiet
           )
  end

  test "running twice does not send a second email for the same enrollment" do
    enrolled_with_stale_progress(20)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])
    assert_email_sent()

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{}, [])
    assert_no_email_sent()

    assert Repo.aggregate(Notification, :count) == 1
  end

  test "a touch: 2 job sends the touch 2 email once touch 1 is old enough" do
    %{user: user, course: course} = enrolled_with_stale_progress(30)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{"touch" => 1}, [])
    assert_email_sent(subject: "Pick up right where you left off in \"#{course.title}\"")

    touch1 =
      Repo.get_by!(Notification,
        user_id: user.id,
        course_id: course.id,
        kind: :reengagement_gone_quiet
      )

    backdate_notification!(touch1, 15)

    assert :ok = Oban.Testing.perform_job(SendGoneQuietReengagement, %{"touch" => 2}, [])
    assert_email_sent(subject: "Your progress in \"#{course.title}\" is still saved")

    assert Repo.get_by(Notification,
             user_id: user.id,
             course_id: course.id,
             kind: :reengagement_gone_quiet_2
           )
  end

  defp backdate_notification!(%Notification{id: id}, days) do
    sent_at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    Notification
    |> where([n], n.id == ^id)
    |> Repo.update_all(set: [inserted_at: sent_at])
  end

  defp enrolled_with_zero_progress(days) do
    user = user_fixture()
    course = course_fixture(status: :published)
    course_module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: course_module.id, position: 1, duration_seconds: 100)

    enrolled_at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    enrollment_fixture(
      user_id: user.id,
      course_id: course.id,
      status: :active,
      enrolled_at: enrolled_at
    )

    %{user: user, course: course, lecture: lecture}
  end

  defp enrolled_with_stale_progress(days) do
    %{user: user, lecture: lecture} = context = enrolled_with_zero_progress(days)
    {:ok, _progress, _events} = Learning.record_progress(user, lecture, 1)

    stale_at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    LectureProgress
    |> where([p], p.user_id == ^user.id and p.lecture_id == ^lecture.id)
    |> Repo.update_all(set: [updated_at: stale_at])

    context
  end
end
