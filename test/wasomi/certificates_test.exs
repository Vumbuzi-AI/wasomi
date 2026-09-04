defmodule Wasomi.CertificatesTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures
  import Wasomi.LearningFixtures
  import Mox

  alias Wasomi.Certificates
  alias Wasomi.Certificates.Branding
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Certificates.VerificationQR
  alias Wasomi.Certificates.Workers.IssueCertificate

  setup :verify_on_exit!

  # The renderer is "up" by default; individual tests override to exercise
  # the browserless / preflight path.
  setup do
    stub(Wasomi.CertificateRendererMock, :available?, fn -> true end)
    :ok
  end

  setup do
    user = user_fixture()

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

    %{user: user, course: course, module: module, lecture: lecture}
  end

  test "enqueue_for_completion_events/2 ignores :module_completed entirely", context do
    assert :ok =
             Certificates.enqueue_for_completion_events(context.user, [
               {:module_completed, context.module}
             ])

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.worker == "Wasomi.Certificates.Workers.IssueCertificate"
             ),
             :count
           ) == 0
  end

  test "course completion enqueues and issues a course certificate while module completion is ignored",
       context do
    expect_render_and_upload(1)

    assert {:ok, _, [_lecture, {:module_completed, _}, {:course_completed, _}]} =
             complete_lecture_via_progress!(context.user, context.lecture)

    # Only the course completion enqueues a certificate job — module
    # completion is still tracked/broadcast (dashboard, course player), it
    # just doesn't trigger its own certificate anymore.
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
    assert Enum.map(certificates, & &1.type) == [:course]
    company_prefix = Application.fetch_env!(:wasomi, :certificate_gdti)[:company_prefix]
    assert Enum.all?(certificates, &String.starts_with?(&1.gdti, company_prefix))
    assert Enum.all?(certificates, &(String.length(&1.gdti) == 22))
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

  describe "gdti_collision?/1" do
    test "true for a changeset that failed on the :gdti unique constraint", context do
      existing = certificate_fixture(user_id: context.user.id, course_id: context.course.id)

      {:error, changeset} =
        Certificates.create_certificate(%{
          type: :course,
          # Deliberately reusing an already-issued GDTI, for a *different*
          # certificate (different user), to trip the unique constraint the
          # same way a genuine random-collision would.
          gdti: existing.gdti,
          file_key: "certificates/collision-test.pdf",
          issued_at: DateTime.utc_now() |> DateTime.truncate(:second),
          user_id: user_fixture().id,
          course_id: course_fixture().id
        })

      assert Certificates.gdti_collision?(changeset)
    end

    test "false for any other kind of changeset failure" do
      {:error, changeset} = Certificates.create_certificate(%{})

      refute Certificates.gdti_collision?(changeset)
    end
  end

  describe "verify_gdti/1" do
    test "finds a certificate by its exact GDTI, preloaded for display", context do
      certificate =
        certificate_fixture(
          user_id: context.user.id,
          course_id: context.course.id,
          type: :course
        )

      assert {:ok, found} = Certificates.verify_gdti(certificate.gdti)
      assert found.id == certificate.id
      assert found.user.id == context.user.id
      assert found.course.id == context.course.id
    end

    test "returns :not_found for a GDTI that doesn't match any certificate" do
      assert {:error, :not_found} = Certificates.verify_gdti("not-a-real-gdti")
    end

    test "returns :not_found rather than raising on non-string input" do
      assert {:error, :not_found} = Certificates.verify_gdti(nil)
      assert {:error, :not_found} = Certificates.verify_gdti(123)
    end
  end

  test "issue_new/3 passes the course's signatory details and the fixed issuer branding into the renderer assigns",
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
        "certificate_signatory_name" => "Jane Doe",
        "certificate_signatory_title" => "Country Manager",
        "certificate_signature_key" => "https://example.com/sig.png"
      })

    expect(Wasomi.CertificateRendererMock, :render, fn assigns ->
      # issuer_name is app-wide branding (Wasomi.Certificates.Branding), not
      # a per-course value — it's the same regardless of what this course's
      # certificate settings are.
      assert assigns.issuer_name == Branding.issuer_name()
      assert assigns.signatory_name == "Jane Doe"
      assert assigns.signatory_title == "Country Manager"
      assert assigns.signature_url == "https://example.com/sig.png"

      assert "data:image/png;base64," <> _base64 = assigns.qr_data_uri

      assert VerificationQR.verification_url(assigns.gdti) =~
               "/certificates/253/#{assigns.gdti}"

      {:ok, "%PDF-test"}
    end)

    expect(Wasomi.CertificateStorageMock, :upload, fn _key, _pdf, "application/pdf" -> :ok end)
    stub(Wasomi.CertificateRendererMock, :render_preview, fn _assigns -> {:ok, "PNG-test"} end)
    stub(Wasomi.CertificateStorageMock, :upload, fn _key, _png, "image/png" -> :ok end)

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    assert {:ok, _certificate, :created} =
             Certificates.issue(context.user.id, context.course.id)
  end

  test "issue/3 refuses to issue a new certificate when the course has certificates disabled",
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

  test "IssueCertificate worker cancels instead of retrying when certificates are disabled",
       context do
    {:ok, _course} =
      Wasomi.Catalog.update_course_certificate(context.course, %{
        "certificate_enabled" => "false"
      })

    {:ok, _, _events} =
      complete_lecture_via_progress!(context.user, context.lecture)

    # {:cancel, _} not {:error, _}: no retry burn for a deterministic condition,
    # but still re-enqueueable by the sweep if it's re-enabled later.
    assert {:cancel, :certificates_disabled} =
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

  describe "ensure_issued/2" do
    test "returns the existing certificate when one is already issued", context do
      certificate = certificate_fixture(user_id: context.user.id, course_id: context.course.id)

      assert {:ok, %Certificate{id: id}} =
               Certificates.ensure_issued(context.user, context.course)

      assert id == certificate.id
      refute_enqueued(worker: IssueCertificate)
    end

    test "enqueues a job for a completed course with no certificate", context do
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert :enqueued = Certificates.ensure_issued(context.user, context.course)
      assert_enqueued(worker: IssueCertificate, args: %{"user_id" => context.user.id})
    end

    test "re-enqueues after a previous job finished (relaxed unique states)", context do
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert :enqueued = Certificates.ensure_issued(context.user, context.course)

      # Simulate the first job reaching a terminal state.
      Repo.update_all(
        from(j in Oban.Job, where: j.worker == "Wasomi.Certificates.Workers.IssueCertificate"),
        set: [state: "cancelled", cancelled_at: DateTime.utc_now()]
      )

      assert :enqueued = Certificates.ensure_issued(context.user, context.course)

      available =
        Repo.aggregate(
          from(j in Oban.Job,
            where:
              j.worker == "Wasomi.Certificates.Workers.IssueCertificate" and
                j.state == "available"
          ),
          :count
        )

      assert available == 1
    end

    test "refuses a course that isn't complete", context do
      assert {:error, :incomplete} = Certificates.ensure_issued(context.user, context.course)
      refute_enqueued(worker: IssueCertificate)
    end

    test "refuses a course with certificates disabled", context do
      {:ok, _} =
        Wasomi.Catalog.update_course_certificate(context.course, %{
          "certificate_enabled" => "false"
        })

      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert {:error, :certificates_disabled} =
               Certificates.ensure_issued(context.user, context.course)
    end
  end

  describe "worker error classification" do
    test "a browserless host cancels the job instead of retrying", context do
      stub(Wasomi.CertificateRendererMock, :available?, fn -> false end)
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert {:cancel, :renderer_unavailable} =
               Oban.Testing.perform_job(
                 IssueCertificate,
                 %{user_id: context.user.id, course_id: context.course.id},
                 []
               )

      assert Repo.aggregate(Certificate, :count) == 0
    end

    test "a transient render failure is retried", context do
      expect(Wasomi.CertificateRendererMock, :render, fn _ -> {:error, :timeout} end)
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert {:error, :timeout} =
               Oban.Testing.perform_job(
                 IssueCertificate,
                 %{user_id: context.user.id, course_id: context.course.id},
                 []
               )
    end
  end

  describe "pending_certificate_courses/1 and the sweep" do
    test "lists a completed course still missing its certificate", context do
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)

      assert [%{id: id}] = Certificates.pending_certificate_courses(context.user)
      assert id == context.course.id

      certificate_fixture(user_id: context.user.id, course_id: context.course.id)
      assert Certificates.pending_certificate_courses(context.user) == []
    end

    test "SweepMissingCertificates enqueues for each pending course", context do
      {:ok, _, _} = complete_lecture_via_progress!(context.user, context.lecture)
      # Drop the job the inline completion path enqueued.
      Repo.delete_all(
        from(j in Oban.Job, where: j.worker == "Wasomi.Certificates.Workers.IssueCertificate")
      )

      refute_enqueued(worker: IssueCertificate)

      assert :ok =
               Oban.Testing.perform_job(
                 Wasomi.Certificates.Workers.SweepMissingCertificates,
                 %{},
                 []
               )

      assert_enqueued(worker: IssueCertificate, args: %{"course_id" => context.course.id})
    end
  end

  defp expect_render_and_upload(count) do
    expect(Wasomi.CertificateRendererMock, :render, count, fn assigns ->
      assert assigns.learner_name
      assert assigns.title
      assert assigns.gdti
      {:ok, "%PDF-test"}
    end)

    expect(Wasomi.CertificateStorageMock, :upload, count, fn key, pdf, "application/pdf" ->
      assert String.ends_with?(key, ".pdf")
      assert pdf == "%PDF-test"
      :ok
    end)

    stub(Wasomi.CertificateRendererMock, :render_preview, fn _assigns -> {:ok, "PNG-test"} end)
    stub(Wasomi.CertificateStorageMock, :upload, fn _key, _png, "image/png" -> :ok end)
  end
end
