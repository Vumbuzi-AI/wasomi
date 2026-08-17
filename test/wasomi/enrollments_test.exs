defmodule Wasomi.EnrollmentsTest do
  use Wasomi.DataCase

  import Mox
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Enrollments

  setup :verify_on_exit!

  test "pending enrollment is unique and never grants course access" do
    user = user_fixture()
    course = course_fixture()

    assert {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    assert {:ok, same} = Enrollments.create_pending_enrollment(user, course)
    assert pending.id == same.id
    assert Enrollments.enrolled?(user, course)
    refute Enrollments.can_access_course?(user, course)
    assert Enrollments.active_enrollment(user, course) == nil
  end

  test "activation grants course and lecture access" do
    user = user_fixture()
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)

    assert {:ok, active} = Enrollments.activate_enrollment(pending)
    assert active.status == :active
    assert active.activated_at
    assert Enrollments.can_access_course?(user, course)
    assert Enrollments.can_access_lecture?(user, lecture)
    assert {:ok, ^lecture} = Enrollments.authorize_lecture(user, lecture)
  end

  describe "enroll_free_course/2" do
    test "creates and auto-activates enrollment for a free course" do
      user = user_fixture()
      free_course = course_fixture(is_free: true, price_minor: nil)

      assert {:ok, enrollment} = Enrollments.enroll_free_course(user, free_course)
      assert enrollment.status == :active
      assert enrollment.activated_at
      assert Enrollments.can_access_course?(user, free_course)
    end

    test "refuses to enroll a paid course as free" do
      user = user_fixture()
      paid_course = course_fixture(is_free: false, price_minor: 15_000)

      assert {:error, :course_not_free} = Enrollments.enroll_free_course(user, paid_course)
      refute Enrollments.can_access_course?(user, paid_course)
    end
  end

  test "playback provider is never called without an active enrollment" do
    user = user_fixture()
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)

    assert {:error, :forbidden} =
             Wasomi.Media.playback_token(user, lecture, 300, Wasomi.MediaProviderMock)
  end

  test "playback tokens may be requested only after activation" do
    user = user_fixture()
    course = course_fixture()
    module = course_module_fixture(course_id: course.id)
    lecture = lecture_fixture(module_id: module.id)
    {:ok, pending} = Enrollments.create_pending_enrollment(user, course)
    {:ok, _active} = Enrollments.activate_enrollment(pending)

    expect(Wasomi.MediaProviderMock, :playback_token, fn ^lecture, ^user, 300 ->
      {:ok, "signed-token"}
    end)

    assert {:ok, "signed-token"} =
             Wasomi.Media.playback_token(user, lecture, 300, Wasomi.MediaProviderMock)
  end

  describe "the pay-gate has no admin bypass" do
    defp admin_fixture(attrs \\ %{}) do
      user = user_fixture(attrs)
      {:ok, admin} = Wasomi.Accounts.update_user_role(user, :admin)
      admin
    end

    test "an admin with no enrollment is gated the same as any other user" do
      admin = admin_fixture()
      course = course_fixture(status: :draft)

      refute Enrollments.enrolled?(admin, course)
      refute Enrollments.can_access_course?(admin, course)
      assert {:error, :forbidden} = Enrollments.authorize_course(admin, course)
    end

    test "an admin with no enrollment cannot access a lecture either" do
      admin = admin_fixture()
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id)

      refute Enrollments.can_access_lecture?(admin, lecture)
      assert {:error, :forbidden} = Enrollments.authorize_lecture(admin, lecture)
    end

    test "a learner with no enrollment is gated the same way" do
      learner = user_fixture()
      course = course_fixture(status: :draft)

      refute Enrollments.can_access_course?(learner, course)
      assert {:error, :forbidden} = Enrollments.authorize_course(learner, course)
    end
  end

  describe "Media.playback_url_for_preview/4" do
    test "signs a playback URL for an admin with no enrollment" do
      admin = admin_fixture()
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id)

      expect(Wasomi.MediaProviderMock, :playback_token, fn ^lecture, ^admin, 300 ->
        {:ok, "signed-token"}
      end)

      assert {:ok, %{url: url}} =
               Wasomi.Media.playback_url_for_preview(
                 admin,
                 lecture,
                 300,
                 Wasomi.MediaProviderMock
               )

      assert url =~ "signed-token"
    end

    test "the regular pay-gated playback_url/4 still refuses the same admin" do
      admin = admin_fixture()
      course = course_fixture(status: :draft)
      module = course_module_fixture(course_id: course.id)
      lecture = lecture_fixture(module_id: module.id)

      assert {:error, :forbidden} =
               Wasomi.Media.playback_url(admin, lecture, 300, Wasomi.MediaProviderMock)
    end
  end

  describe "grant_access/3" do
    test "activates the course, writes a permanent audit entry, and notifies the learner" do
      learner = user_fixture()
      admin = admin_fixture()
      course = course_fixture(title: "Negotiation Mastery", status: :published)

      assert {:ok, enrollment} =
               Enrollments.grant_access(learner, admin, %{
                 "course_id" => course.id,
                 "reason" => "Manual enrollment for a partner scholarship"
               })

      assert enrollment.status == :active
      assert enrollment.activated_at
      assert Enrollments.can_access_course?(learner, course)

      assert [audit] = Enrollments.list_audits_for_enrollment(enrollment.id)
      assert audit.admin_user.id == admin.id
      assert audit.reason == "Manual enrollment for a partner scholarship"

      assert_email_sent(subject: "You now have access to Negotiation Mastery")

      assert [notification] = Wasomi.Notifications.list_unread_for_user(learner)
      assert notification.kind == :enrollment_granted
      assert notification.body =~ "Negotiation Mastery"
    end

    test "rejects a blank or too-short reason without touching enrollment state" do
      learner = user_fixture()
      admin = admin_fixture()
      course = course_fixture()

      assert {:error, changeset} =
               Enrollments.grant_access(learner, admin, %{
                 "course_id" => course.id,
                 "reason" => "too short"
               })

      assert %{reason: ["should be at least 10 character(s)"]} = errors_on(changeset)
      refute Enrollments.can_access_course?(learner, course)
    end

    test "rejects a missing course selection" do
      learner = user_fixture()
      admin = admin_fixture()

      assert {:error, changeset} =
               Enrollments.grant_access(learner, admin, %{
                 "reason" => "Manual enrollment for a partner scholarship"
               })

      assert %{course_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses to grant access the learner already actively has" do
      learner = user_fixture()
      admin = admin_fixture()
      course = course_fixture(status: :published)

      {:ok, pending} = Enrollments.create_pending_enrollment(learner, course)
      {:ok, _active} = Enrollments.activate_enrollment(pending)

      assert {:error, changeset} =
               Enrollments.grant_access(learner, admin, %{
                 "course_id" => course.id,
                 "reason" => "Manual enrollment for a partner scholarship"
               })

      assert %{course_id: ["learner already has active access"]} = errors_on(changeset)
    end

    test "refuses to grant access to a draft or archived course" do
      learner = user_fixture()
      admin = admin_fixture()
      draft = course_fixture(status: :draft)
      archived = course_fixture(status: :archived)

      for course <- [draft, archived] do
        assert {:error, changeset} =
                 Enrollments.grant_access(learner, admin, %{
                   "course_id" => course.id,
                   "reason" => "Manual enrollment for a partner scholarship"
                 })

        assert %{course_id: ["is not published"]} = errors_on(changeset)
        refute Enrollments.can_access_course?(learner, course)
      end
    end

    test "refuses to grant access when the performing user is not an admin" do
      learner = user_fixture()
      non_admin = user_fixture(role: :learner)
      course = course_fixture()

      assert {:error, :forbidden} =
               Enrollments.grant_access(learner, non_admin, %{
                 "course_id" => course.id,
                 "reason" => "Manual enrollment for a partner scholarship"
               })

      refute Enrollments.can_access_course?(learner, course)
    end
  end

  describe "count_by_course/0" do
    test "counts enrollments of any status, keyed by course" do
      course = course_fixture()
      enrollment_fixture(course_id: course.id, status: :pending)
      enrollment_fixture(course_id: course.id, status: :active)
      other_course = course_fixture()
      enrollment_fixture(course_id: other_course.id, status: :active)

      counts = Enrollments.count_by_course()

      assert counts[course.id] == 2
      assert counts[other_course.id] == 1
    end
  end
end
