defmodule Wasomi.CertificatesTest do
  use Wasomi.DataCase

  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.CertificatesFixtures
  import Wasomi.EnrollmentsFixtures
  import Mox

  alias Wasomi.Certificates
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Certificates.Workers.IssueCertificate
  alias Wasomi.Learning

  setup :verify_on_exit!

  setup do
    user = user_fixture()
    course = course_fixture(status: :published)
    module = course_module_fixture(course_id: course.id, position: 1)
    lecture = lecture_fixture(module_id: module.id, position: 1, duration_seconds: 100)
    enrollment_fixture(user_id: user.id, course_id: course.id, status: :active)

    %{user: user, course: course, module: module, lecture: lecture}
  end

  test "completion enqueues and issues module and course certificates", context do
    expect_render_and_upload(2)

    assert {:ok, _, [_lecture, {:module_completed, _}, {:course_completed, _}]} =
             Learning.mark_complete(context.user, context.lecture)

    assert Repo.aggregate(
             from(job in Oban.Job,
               where: job.worker == "Wasomi.Certificates.Workers.IssueCertificate"
             ),
             :count
           ) == 2

    assert :ok =
             Oban.Testing.perform_job(
               IssueCertificate,
               %{
                 user_id: context.user.id,
                 type: "module",
                 scope_id: context.module.id
               },
               []
             )

    assert :ok =
             Oban.Testing.perform_job(
               IssueCertificate,
               %{
                 user_id: context.user.id,
                 type: "course",
                 scope_id: context.course.id
               },
               []
             )

    certificates = Certificates.list_for_user_course(context.user, context.course)
    assert Enum.map(certificates, & &1.type) |> Enum.sort() == [:course, :module]
    assert Enum.all?(certificates, &String.starts_with?(&1.serial_number, "KBI-"))
    assert Enum.uniq_by(certificates, & &1.serial_number) == certificates
  end

  test "issuance is idempotent and doesn't render or upload twice", context do
    expect_render_and_upload(1)
    {:ok, _, _events} = Learning.mark_complete(context.user, context.lecture)

    args = %{
      user_id: context.user.id,
      type: "module",
      scope_id: context.module.id
    }

    assert :ok = Oban.Testing.perform_job(IssueCertificate, args, [])
    assert :ok = Oban.Testing.perform_job(IssueCertificate, args, [])

    assert Repo.aggregate(
             from(certificate in Certificate,
               where:
                 certificate.user_id == ^context.user.id and
                   certificate.module_id == ^context.module.id
             ),
             :count
           ) == 1
  end

  test "refuses to issue before the scope is complete", context do
    assert {:error, :incomplete} =
             Certificates.issue(context.user.id, :module, context.module.id)

    assert Repo.aggregate(Certificate, :count) == 0
  end

  test "signed downloads are learner-owned and short lived", context do
    certificate =
      certificate_fixture(
        user_id: context.user.id,
        course_id: context.course.id,
        module_id: context.module.id
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
