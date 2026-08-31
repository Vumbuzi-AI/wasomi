defmodule Wasomi.Certificates do
  @moduledoc """
  Issues and serves learner-owned course certificates.

  Scope uniqueness is enforced both by Oban and a partial database index on
  `(user_id, course_id)` — that's what makes a duplicate issuance attempt
  (e.g. a worker retry after uploading but before inserting the database
  row) safe: it always hits the same deterministic `file_key`, and whichever
  insert loses the scope-uniqueness race falls back to fetching the
  certificate the winner created. The GDTI itself is randomly generated per
  issuance (see `Wasomi.Certificates.GDTI`) and plays no part in that
  idempotency — it only needs to be unique, not deterministic.

  Module-level certificates existed briefly and were removed: a formal,
  individually GDTI-verifiable certificate per module (10+ for a single
  course purchase) diluted what a Wasomi certificate means far more than it
  added, without a matching increase in real credentialing value. Module
  completion is still tracked and still fires a `:module_completed` event
  (dashboard/course-player progress UI listens for it), it just doesn't
  issue anything.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Course
  alias Wasomi.Certificates.Branding
  alias Wasomi.Certificates.Certificate
  alias Wasomi.Certificates.GDTI
  alias Wasomi.Certificates.VerificationQR
  alias Wasomi.Certificates.Workers.IssueCertificate
  alias Wasomi.Learning
  alias Wasomi.Repo

  @download_ttl 300

  def list_certificates do
    Certificate
    |> order_by([certificate], desc: certificate.issued_at)
    |> Repo.all()
  end

  @doc """
  Counts certificates issued, optionally scoped to a single course. Used by
  the admin conversion funnel as its terminal "Certified" step.
  """
  def count_course_certificates(opts \\ []) do
    course_id = Keyword.get(opts, :course_id)

    Certificate
    |> filter_course(course_id)
    |> Repo.aggregate(:count)
  end

  defp filter_course(query, nil), do: query
  defp filter_course(query, course_id), do: where(query, [c], c.course_id == ^course_id)

  def list_for_user(%User{id: user_id}) do
    Certificate
    |> where([certificate], certificate.user_id == ^user_id)
    |> order_by([certificate], desc: certificate.issued_at)
    |> preload(:course)
    |> Repo.all()
  end

  @doc """
  Lists certificates safe to show on a learner's public profile.

  This intentionally returns verification metadata only; callers should link
  to the public GDTI verification page rather than exposing certificate files.
  """
  def list_public_for_user(%User{id: user_id, public_profile_enabled: true}) do
    Certificate
    |> where([certificate], certificate.user_id == ^user_id)
    |> order_by([certificate], desc: certificate.issued_at)
    |> preload(:course)
    |> Repo.all()
  end

  def list_public_for_user(%User{}), do: []

  def list_for_user_course(%User{id: user_id}, %Course{id: course_id}) do
    Certificate
    |> where(
      [certificate],
      certificate.user_id == ^user_id and certificate.course_id == ^course_id
    )
    |> order_by([certificate], asc: certificate.issued_at)
    |> preload(:course)
    |> Repo.all()
  end

  def get_certificate!(id), do: Repo.get!(Certificate, id)

  def get_user_certificate!(%User{id: user_id}, id) do
    Certificate
    |> where([certificate], certificate.id == ^id and certificate.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc """
  Looks up a certificate by its public GDTI, for the unauthenticated
  certificate-verification page. Unlike `get_certificate!/1` and
  `get_user_certificate!/2`, this never raises on a miss — an unrecognized
  or tampered-with identifier is an expected, ordinary outcome here (a
  mistyped code, a stale/fake QR), not a bug, so callers get a plain
  `{:error, :not_found}` to render a "not verified" state with rather than
  a 404/500 page.
  """
  def verify_gdti(gdti) when is_binary(gdti) do
    case Repo.get_by(Certificate, gdti: gdti) do
      %Certificate{} = certificate -> {:ok, preload_certificate(certificate)}
      nil -> {:error, :not_found}
    end
  end

  def verify_gdti(_gdti), do: {:error, :not_found}

  def create_certificate(attrs \\ %{}) do
    %Certificate{}
    |> Certificate.changeset(attrs)
    |> Repo.insert()
  end

  def update_certificate(%Certificate{} = certificate, attrs) do
    certificate
    |> Certificate.changeset(attrs)
    |> Repo.update()
  end

  def delete_certificate(%Certificate{} = certificate), do: Repo.delete(certificate)

  def change_certificate(%Certificate{} = certificate, attrs \\ %{}) do
    Certificate.changeset(certificate, attrs)
  end

  @doc """
  Enqueues a certificate job for a newly completed course. Any other event
  (including `:module_completed`) is ignored — see the moduledoc.
  """
  def enqueue_for_completion_events(%User{} = user, events) when is_list(events) do
    events
    |> Enum.flat_map(fn
      {:course_completed, %Course{id: scope_id}} ->
        [IssueCertificate.for_completion(user.id, scope_id)]

      _ ->
        []
    end)
    |> Enum.map(&Oban.insert/1)
    |> then(fn results ->
      if Enum.all?(results, &match?({:ok, _}, &1)), do: :ok, else: {:error, results}
    end)
  end

  @doc """
  Performs one idempotent issuance after re-checking completion.
  """
  def issue(user_id, course_id) do
    with %User{} = user <- Repo.get(User, user_id),
         {:ok, course} <- load_completed_course(user, course_id) do
      case get_by_course(user.id, course_id) do
        %Certificate{} = certificate ->
          {:ok, preload_certificate(certificate), :existing}

        nil ->
          if course.certificate_enabled do
            issue_new(user, course)
          else
            {:error, :certificates_disabled}
          end
      end
    else
      nil -> {:error, :user_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def subscribe(%User{id: id}) do
    Phoenix.PubSub.subscribe(Wasomi.PubSub, user_topic(id))
  end

  def broadcast_ready(%Certificate{} = certificate) do
    Phoenix.PubSub.broadcast(
      Wasomi.PubSub,
      user_topic(certificate.user_id),
      {:certificate_ready, certificate}
    )
  end

  def download_url(%User{} = user, certificate_or_id, opts \\ []) do
    certificate =
      case certificate_or_id do
        %Certificate{} = certificate -> certificate
        id -> get_user_certificate!(user, id)
      end

    if certificate.user_id == user.id do
      certificate = Repo.preload(certificate, :course)

      storage().signed_url(
        certificate.file_key,
        opts
        |> Keyword.put_new(:expires_in, @download_ttl)
        |> Keyword.put_new(:filename, certificate_filename(certificate))
      )
    else
      {:error, :forbidden}
    end
  end

  @doc "Signed URL for a certificate's PNG preview image."
  def preview_url(%User{} = user, %Certificate{} = certificate) do
    if certificate.user_id == user.id do
      storage().signed_url(preview_key(certificate.file_key),
        expires_in: @download_ttl,
        content_type: "image/png"
      )
    else
      {:error, :forbidden}
    end
  end

  @doc """
  A descriptive, filesystem-safe filename for a certificate's PDF download —
  e.g. `"GS1 Barcoding Fundamentals - Wasomi Certificate.pdf"` — instead of
  the bare numeric course id the download used to save as (the object
  storage key's own basename, with no filename hint given to the browser).
  """
  def certificate_filename(%Certificate{} = certificate) do
    certificate = Repo.preload(certificate, :course)

    "#{certificate.course.title} - Wasomi Certificate.pdf"
    |> String.replace(~r/[\/\\:*?"<>|]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # LinkedIn's own "Add to Profile" deep link for certifications — see
  # https://learn.microsoft.com/linkedin/consumer/integrations/self-serve/add-to-profile
  # (LinkedIn's own docs on this have moved around over the years; Microsoft's
  # mirror has stayed put). Opens LinkedIn's "Add certification" form
  # pre-filled from these params; the learner just reviews and saves — no
  # OAuth, no LinkedIn API, no consent screen, since it's a plain deep link
  # rather than a real integration.
  #
  # `organizationName` pre-fills the issuer as plain text either way; giving
  # LinkedIn the numeric `organizationId` instead upgrades that to a real,
  # verified link to the issuer's Company Page. Add `organization_id: <id>`
  # to `:certificate_branding` once GS1 Kenya's page exists, and this picks
  # it up automatically (organizationName stays as a fallback for whoever
  # doesn't have theirs set).
  @doc """
  Builds the LinkedIn "Add to Profile" URL for a certificate, pre-filled
  with the course title, issuing organization, issue date, and this
  certificate's verification URL and GDTI as its credential ID.
  """
  def linkedin_add_to_profile_url(%Certificate{} = certificate) do
    certificate = Repo.preload(certificate, :course)
    issued_on = certificate.issued_at

    params =
      [
        startTask: "CERTIFICATION_NAME",
        name: certificate.course.title,
        organizationName: Branding.issuer_name(),
        issueYear: issued_on.year,
        issueMonth: issued_on.month,
        certUrl: VerificationQR.verification_url(certificate.gdti),
        certId: certificate.gdti
      ]
      |> maybe_put_organization_id()

    "https://www.linkedin.com/profile/add?" <> URI.encode_query(params)
  end

  defp maybe_put_organization_id(params) do
    case Application.get_env(:wasomi, :certificate_branding, [])[:organization_id] do
      nil -> params
      id -> Keyword.put(params, :organizationId, id)
    end
  end

  # A collision between two different certificates' randomly generated
  # GDTIs is astronomically unlikely (see Wasomi.Certificates.GDTI's
  # moduledoc), but the DB's unique index on :gdti makes it a real,
  # checkable failure mode rather than a silent bug — so on that specific
  # error, regenerate a fresh GDTI and retry rather than failing the
  # learner's issuance outright over a one-in-a-billion coin flip. The PDF
  # has the GDTI printed on it and QR-encoded, so a retry re-renders and
  # re-uploads too, not just the DB insert — swapping the GDTI without
  # updating the file would print a certificate whose QR doesn't match its
  # own database record.
  @max_gdti_attempts 3

  defp issue_new(user, course), do: issue_new(user, course, @max_gdti_attempts)

  defp issue_new(user, course, attempts_left) do
    issued_at = DateTime.utc_now() |> DateTime.truncate(:second)
    gdti = GDTI.generate()
    file_key = file_key(user.id, course.id)

    assigns =
      Map.merge(Branding.assigns(), %{
        learner_name: user.name,
        title: course.title,
        issued_on: Calendar.strftime(issued_at, "%B %-d, %Y"),
        gdti: gdti,
        qr_data_uri: VerificationQR.data_uri(gdti),
        signatory_name: course.certificate_signatory_name,
        signatory_title: course.certificate_signatory_title,
        signature_url: course.certificate_signature_key,
        signatory_two_name: course.certificate_signatory_two_name,
        signatory_two_title: course.certificate_signatory_two_title,
        signatory_two_signature_url: course.certificate_signatory_two_signature_key
      })

    with {:ok, pdf} <- renderer().render(assigns),
         :ok <- storage().upload(file_key, pdf, "application/pdf"),
         {:ok, certificate} <-
           create_certificate(%{
             type: :course,
             gdti: gdti,
             file_key: file_key,
             issued_at: issued_at,
             user_id: user.id,
             course_id: course.id
           }) do
      upload_preview(assigns, preview_key(file_key))
      {:ok, preload_certificate(certificate), :created}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        if gdti_collision?(changeset) and attempts_left > 1 do
          issue_new(user, course, attempts_left - 1)
        else
          case get_by_course(user.id, course.id) do
            %Certificate{} = certificate -> {:ok, preload_certificate(certificate), :existing}
            nil -> {:error, changeset}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Whether a failed certificate changeset failed specifically because its
  (randomly generated) GDTI collided with an already-issued one — as
  opposed to any other validation failure. Public so the classification
  logic itself has direct test coverage without needing to force a real
  DB-level GDTI collision end-to-end.
  """
  @spec gdti_collision?(Ecto.Changeset.t()) :: boolean()
  def gdti_collision?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:gdti, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _other -> false
    end)
  end

  defp load_completed_course(user, course_id) do
    case Repo.get(Course, course_id) do
      nil ->
        {:error, :scope_not_found}

      course ->
        if Learning.course_complete?(user, course), do: {:ok, course}, else: {:error, :incomplete}
    end
  end

  defp get_by_course(user_id, course_id) do
    Repo.get_by(Certificate, user_id: user_id, course_id: course_id)
  end

  defp preload_certificate(certificate), do: Repo.preload(certificate, [:user, :course])

  defp file_key(user_id, course_id), do: "certificates/#{user_id}/course/#{course_id}.pdf"
  defp preview_key(file_key), do: String.replace_suffix(file_key, ".pdf", ".png")

  # Best-effort: a failed preview shouldn't fail issuance of the real
  # certificate.
  defp upload_preview(assigns, preview_key) do
    with {:ok, png} <- renderer().render_preview(assigns),
         :ok <- storage().upload(preview_key, png, "image/png") do
      :ok
    else
      {:error, reason} ->
        Logger.warning("certificate preview upload failed: #{inspect(reason)}")
    end
  end

  defp renderer, do: Application.fetch_env!(:wasomi, :certificate_renderer)
  defp storage, do: Application.fetch_env!(:wasomi, :certificate_storage)
  defp user_topic(user_id), do: "user:#{user_id}"
end
