defmodule Wasomi.EnrollmentsTest do
  use Wasomi.DataCase

  import Mox
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures

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
end
