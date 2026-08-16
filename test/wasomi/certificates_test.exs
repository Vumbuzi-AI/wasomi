defmodule Wasomi.CertificatesTest do
  use Wasomi.DataCase

  import Wasomi.AccountsFixtures
  import Wasomi.AssessmentsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures
  import Mox

  alias Wasomi.Assessments
  alias Wasomi.Certificates
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Certificates.Workers.IssueCertificate

  setup :verify_on_exit!

  setup do
    user = user_fixture()

    course =
      course_fixture(
        status: :published,
        certificate_enabled: true,
        certificate_issuer_name: "Wasomi Academy",
        certificate_signatory_name: "Jane Doe",
        certificate_signatory_title: "Head of Learning"
      )

    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    %{user: user, course: course, module: module, lecture: lecture}
  end

  test "completion enqueues and issues one course certificate", context do
    expect_render_and_upload(1)

    assert {:ok, _, [_lecture, {:module_completed, _}, {:course_completed, _}]} =
             complete_lecture_via_progress!(context.user, context.lecture)

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.worker == "Wasomi.Certificates.Workers.IssueCertificate"
             ),
             :count
           ) == 1

    assert :ok =
             Oban.Testing.perform_job(
               IssueCertificate,
               %{
                 user_id: context.user.id,
                 course_id: context.course.id
               },
               []
             )

    certificates = Certificates.list_for_user_course(context.user, context.course)
    assert [%{type: :course, serial_number: "KBI-CRS-" <> _}] = certificates
  end

  test "issuance is idempotent and doesn't render or upload twice", context do
    expect_render_and_upload(1)

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    args = %{
      user_id: context.user.id,
      course_id: context.course.id
    }

    assert :ok = Oban.Testing.perform_job(IssueCertificate, args, [])
    assert :ok = Oban.Testing.perform_job(IssueCertificate, args, [])

    assert Repo.aggregate(
             from(certificate in Certificate,
               where:
                 certificate.user_id == ^context.user.id and
                   certificate.course_id == ^context.course.id
             ),
             :count
           ) == 1
  end

  test "refuses to issue before the scope is complete", context do
    assert {:error, :incomplete} =
             Certificates.issue(context.user.id, context.course.id)

    assert Repo.aggregate(Certificate, :count) == 0
  end

  test "keeps the course certificate locked until its required quiz is passed", context do
    expect_render_and_upload(1)
    quiz = quiz_fixture(module: context.module)
    question = question_fixture(quiz: quiz)
    correct_option = Enum.find(question.question_options, & &1.correct)

    assert {:ok, _, [_lecture, {:module_completed, _}]} =
             complete_lecture_via_progress!(context.user, context.lecture)

    assert {:error, :incomplete} = Certificates.issue(context.user.id, context.course.id)

    assert {:ok, %{passed: true}} =
             Assessments.submit_quiz(context.user, quiz, %{question.id => correct_option.id})

    assert :ok =
             Oban.Testing.perform_job(
               IssueCertificate,
               %{user_id: context.user.id, course_id: context.course.id},
               []
             )

    assert [%{type: :course}] = Certificates.list_for_user_course(context.user, context.course)
  end

  test "signed downloads are learner-owned and short lived", context do
    certificate =
      certificate_fixture(
        user_id: context.user.id,
        course_id: context.course.id
      )

    expect(Wasomi.CertificateStorageMock, :signed_url, fn key, opts ->
      assert key == certificate.file_key
      assert opts[:expires_in] == 300
      {:ok, "https://r2.example.test/signed"}
    end)

    assert {:ok, "https://r2.example.test/signed"} =
             Certificates.download_url(context.user, certificate)

    assert {:error, :forbidden} =
             Certificates.download_url(user_fixture(), certificate)
  end

  test "issue_new/3 passes the course's certificate branding into the renderer assigns",
       context do
    # A locally configured R2_PUBLIC_URL (via .env) would otherwise make this
    # test's signature host-trust check depend on the developer's machine
    # instead of being deterministic.
    previous = Application.get_env(:wasomi, :r2_public_url)
    on_exit(fn -> Application.put_env(:wasomi, :r2_public_url, previous) end)
    Application.put_env(:wasomi, :r2_public_url, "https://example.com")

    {:ok, _course} =
      Wasomi.Catalog.update_course_certificate(context.course, %{
        "certificate_enabled" => "true",
        "certificate_issuer_name" => "GS1 Kenya",
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager",
        "certificate_signature_key" => "https://example.com/sig.png"
      })

    expect(Wasomi.CertificateRendererMock, :render, fn assigns ->
      assert assigns.issuer_name == "GS1 Kenya"
      assert assigns.signatory_name == "Jane Doe"
      assert assigns.signatory_title == "Country Manager"
      assert assigns.signature_url == "https://example.com/sig.png"
      {:ok, "%PDF-test"}
    end)

    expect(Wasomi.CertificateStorageMock, :upload, fn _key, _pdf -> :ok end)

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    assert {:ok, _certificate, :created} =
             Certificates.issue(context.user.id, context.course.id)
  end

  test "issue/2 refuses to issue a new certificate when the course has certificates disabled",
       context do
    {:ok, _course} =
      Wasomi.Catalog.update_course_certificate(context.course, %{
        "certificate_enabled" => "false"
      })

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    assert {:error, :certificates_disabled} =
             Certificates.issue(context.user.id, context.course.id)

    assert Repo.aggregate(Certificate, :count) == 0
  end

  test "IssueCertificate worker succeeds as a no-op instead of retrying when certificates are disabled",
       context do
    {:ok, _course} =
      Wasomi.Catalog.update_course_certificate(context.course, %{
        "certificate_enabled" => "false"
      })

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    # :ok (not {:error, _}) is the whole point here — Oban retries any
    # {:error, _} return up to max_attempts, which would be pointless for a
    # deterministic "admin turned this off" condition.
    assert :ok =
             Oban.Testing.perform_job(
               IssueCertificate,
               %{
                 user_id: context.user.id,
                 course_id: context.course.id
               },
               []
             )

    assert Repo.aggregate(Certificate, :count) == 0
  end

  defp expect_render_and_upload(count) do
    expect(Wasomi.CertificateRendererMock, :render, count, fn assigns ->
      assert assigns.learner_name
      assert assigns.title
      assert assigns.serial_number
      {:ok, "%PDF-test"}
    end)

    expect(Wasomi.CertificateStorageMock, :upload, count, fn key, pdf ->
      assert String.ends_with?(key, ".pdf")
      assert pdf == "%PDF-test"
      :ok
    end)
  end
end
