defmodule WasomiWeb.CertificatesLiveTest do
  use WasomiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures

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
end
