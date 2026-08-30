defmodule WasomiWeb.LearnerProfileLiveTest do
  use WasomiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures

  alias Wasomi.Accounts

  test "unavailable state renders for a missing profile", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/learners/not-here")

    assert html =~ "Profile unavailable"
    assert html =~ "private, unpublished, or the link is no longer active"
  end

  test "anonymous visitors get the standalone marketing chrome", %{conn: conn} do
    user = user_fixture(name: "Shell Anon")

    {:ok, _user} =
      Accounts.update_user_public_profile(user, %{
        "public_profile_enabled" => "true",
        "public_profile_slug" => "shell-anon"
      })

    {:ok, view, _html} = live(conn, ~p"/learners/shell-anon")

    assert has_element?(view, "header a", "Explore courses")
    refute has_element?(view, "#student-sidebar")
  end

  test "signed-in learners get the app sidebar shell", %{conn: conn} do
    viewer = user_fixture()
    subject = user_fixture(name: "Shell Subject")

    {:ok, _user} =
      Accounts.update_user_public_profile(subject, %{
        "public_profile_enabled" => "true",
        "public_profile_slug" => "shell-subject"
      })

    {:ok, view, _html} =
      conn |> log_in_user(viewer) |> live(~p"/learners/shell-subject")

    assert has_element?(view, "#student-sidebar")
    assert render(view) =~ "Shell Subject"
  end

  test "private learner profiles are not reachable by slug", %{conn: conn} do
    user = user_fixture(name: "Private Learner")

    {:ok, _user} =
      Accounts.update_user_public_profile(user, %{
        "public_profile_enabled" => "false",
        "public_profile_slug" => "private-learner"
      })

    {:ok, _view, html} = live(conn, ~p"/learners/private-learner")

    assert html =~ "Profile unavailable"
    refute html =~ "Private Learner"
  end

  test "published profile shows approved public fields and hides private contact fields", %{
    conn: conn
  } do
    user =
      user_fixture(
        name: "One Student",
        email: "private-profile@example.com",
        phone: "+254712345678"
      )

    {:ok, user} =
      Accounts.update_user_profile(user, %{
        "headline" => "Supply Chain Analyst",
        "bio" => "Learning GS1 standards.",
        "country" => "Kenya",
        "organization" => "GS1 Kenya",
        "industry" => "Supply Chain & Logistics",
        "occupation" => "Operations Lead",
        "avatar_key" => "https://cdn.example.test/avatars/one.png"
      })

    {:ok, _user} =
      Accounts.update_user_public_profile(user, %{
        "public_profile_enabled" => "true",
        "public_profile_slug" => "one-student",
        "linkedin_url" => "https://www.linkedin.com/in/one-student"
      })

    {:ok, _view, html} = live(conn, ~p"/learners/one-student")

    assert html =~ "One Student"
    assert html =~ "Supply Chain Analyst"
    assert html =~ "Learning GS1 standards."
    assert html =~ "Supply Chain &amp; Logistics"
    assert html =~ "Kenya"
    assert html =~ "https://www.linkedin.com/in/one-student"
    assert html =~ "https://cdn.example.test/avatars/one.png"

    # private: contact details and the biodata that stays off the public page
    refute html =~ "private-profile@example.com"
    refute html =~ "254712345678"
    refute html =~ "Operations Lead"
    refute html =~ "GS1 Kenya"
  end

  test "published certificates appear through verification links, not download links", %{
    conn: conn
  } do
    user = user_fixture(name: "Certified Learner")
    course = course_fixture(title: "Digital Link Foundations", slug: "digital-link-foundations")

    {:ok, user} =
      Accounts.update_user_public_profile(user, %{
        "public_profile_enabled" => "true",
        "public_profile_slug" => "certified-learner"
      })

    certificate = certificate_fixture(user_id: user.id, course_id: course.id)

    {:ok, _view, html} = live(conn, ~p"/learners/certified-learner")

    assert html =~ "Digital Link Foundations"
    assert html =~ ~p"/certificates/253/#{certificate.gdti}"
    refute html =~ "/certificates/#{certificate.id}/download"
    refute html =~ certificate.file_key
  end
end
