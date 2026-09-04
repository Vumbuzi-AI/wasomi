defmodule WasomiWeb.CertificatesLiveTest do
  use WasomiWeb.ConnCase
  use Oban.Testing, repo: Wasomi.Repo

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures

  alias Wasomi.Certificates

  setup :register_and_log_in_user

  test "requires authentication" do
    conn = Plug.Test.init_test_session(build_conn(), %{})

    assert {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/certificates")
  end

  test "shows owned certificate downloads and refreshes when one becomes ready", %{
    conn: conn,
    user: user
  } do
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    {:ok, view, _html} = live(conn, ~p"/certificates")
    refute has_element?(view, "[id^='certificate-']")
    assert has_element?(view, "#certificates-empty")

    certificate =
      certificate_fixture(user_id: user.id, course_id: course.id, module_id: module.id)

    :ok = Certificates.broadcast_ready(certificate)

    assert has_element?(
             view,
             "#certificate-#{certificate.id} a[href='/certificates/#{certificate.id}/download']"
           )
  end

  test "a completed course with no certificate yet shows a preparing row with a working retry", %{
    conn: conn,
    user: user
  } do
    course =
      course_fixture(
        status: :published,
        certificate_enabled: true,
        certificate_signatory_name: "Jane Doe",
        certificate_signatory_title: "Head of Learning"
      )

    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)
    {:ok, _, _} = complete_lecture_via_progress!(user, lecture)

    {:ok, view, _html} = live(conn, ~p"/certificates")

    refute has_element?(view, "#certificates-empty")
    assert has_element?(view, "#certificate-pending-#{course.id}", course.title)

    # Drop the job the completion enqueued so the retry has to create one.
    Wasomi.Repo.delete_all(Oban.Job)

    view
    |> element("#certificate-pending-#{course.id} button", "Retry")
    |> render_click()

    assert_enqueued(
      worker: Wasomi.Certificates.Workers.IssueCertificate,
      args: %{"course_id" => course.id}
    )
  end
end
