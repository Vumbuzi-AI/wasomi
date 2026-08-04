defmodule WasomiWeb.AdminLive.CourseCertificate do
  use WasomiWeb, :live_view

  alias Wasomi.{Catalog, Storage}
  alias Wasomi.Certificates.Template

  @max_signature_bytes 2_000_000
  @sample_serial_number "SAMPLE-0000"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    course = Catalog.get_course!(id)

    {:ok,
     socket
     |> assign(:page_title, "Certificate settings")
     |> assign(:course, course)
     |> assign(:form, to_form(Catalog.change_course_certificate(course)))
     |> assign(:generating_pdf?, false)
     |> allow_upload(:signature,
       accept: ~w(.png),
       max_entries: 1,
       max_file_size: @max_signature_bytes,
       auto_upload: true,
       external: fn entry, socket -> presign_entry(entry, socket, course.id) end,
       progress: &handle_progress/3
     )
     |> assign_preview()}
  end

  @impl true
  def handle_event("validate", %{"course" => params}, socket) do
    changeset =
      socket.assigns.course
      |> Catalog.change_course_certificate(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign_preview()}
  end

  def handle_event("save", %{"course" => params}, socket) do
    case consume_signature_upload(socket) do
      {:ok, url} ->
        save_certificate(socket, Map.put(params, "certificate_signature_key", url))

      :no_upload ->
        save_certificate(socket, params)

      {:error, :missing_public_url} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The signature image uploaded, but no public storage URL is configured " <>
             "(R2_PUBLIC_URL). Nothing was saved — ask an engineer to set it, then re-upload."
         )}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:signature, ref) |> assign_preview()}
  end

  def handle_event("test_pdf", _params, socket) do
    if socket.assigns.generating_pdf? do
      {:noreply, socket}
    else
      assigns = sample_assigns(socket)

      {:noreply,
       socket
       |> assign(:generating_pdf?, true)
       |> start_async(:test_pdf, fn -> renderer().render(assigns) end)}
    end
  end

  def handle_progress(:signature, entry, socket) do
    if entry.done?, do: {:noreply, assign_preview(socket)}, else: {:noreply, socket}
  end

  @impl true
  def handle_async(:test_pdf, {:ok, {:ok, pdf}}, socket) do
    {:noreply,
     socket
     |> assign(:generating_pdf?, false)
     |> push_event("download-pdf", %{data: Base.encode64(pdf), filename: "sample-certificate.pdf"})}
  end

  def handle_async(:test_pdf, {:ok, {:error, _reason}}, socket) do
    {:noreply,
     socket
     |> assign(:generating_pdf?, false)
     |> put_flash(:error, "Could not generate a sample PDF right now.")}
  end

  def handle_async(:test_pdf, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating_pdf?, false)
     |> put_flash(:error, "Could not generate a sample PDF right now.")}
  end

  defp save_certificate(socket, params) do
    case Catalog.update_course_certificate(socket.assigns.course, params) do
      {:ok, course} ->
        {:noreply,
         socket
         |> put_flash(:info, "Certificate settings saved.")
         |> assign(:course, course)
         |> assign(:form, to_form(Catalog.change_course_certificate(course)))
         |> assign_preview()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:courses} current_user={@current_user}>
      <div
        class="mx-auto max-w-container space-y-8 px-5 py-10 lg:px-10"
        id="course-certificate"
        phx-hook="PdfDownload"
      >
        <.link
          navigate={~p"/admin/courses/#{@course.id}"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to {@course.title}
        </.link>

        <h1 class="text-3xl font-semibold text-dark">Certificate settings</h1>

        <div class="grid gap-8 lg:grid-cols-2">
          <section class="rounded-3xl border border-black/5 bg-white p-6">
            <.simple_form for={@form} id="certificate-form" phx-change="validate" phx-submit="save">
              <.input
                field={@form[:certificate_enabled]}
                type="checkbox"
                label="Issue certificates for this course"
              />

              <.input
                field={@form[:certificate_issuer_name]}
                type="text"
                label="Issuer name"
                placeholder="e.g. GS1 Kenya"
              />
              <.input field={@form[:certificate_signatory_name]} type="text" label="Signatory name" />
              <.input field={@form[:certificate_signatory_title]} type="text" label="Signatory title" />

              <div class="hidden">
                <.input field={@form[:certificate_signature_key]} type="text" />
              </div>

              <div class="space-y-3">
                <span class="block text-sm font-semibold leading-6 text-zinc-800">
                  Signature image
                </span>

                <img
                  :if={@signature_url}
                  src={@signature_url}
                  alt=""
                  class="h-16 rounded-lg border border-zinc-200 bg-white object-contain p-2"
                />

                <.live_file_input
                  upload={@uploads.signature}
                  class="block w-full text-sm text-zinc-700"
                />
                <p class="text-xs text-zinc-500">Transparent PNG, up to 2 MB.</p>

                <div :for={entry <- @uploads.signature.entries} class="space-y-1">
                  <div class="flex items-center justify-between gap-3 text-sm text-zinc-700">
                    <span>{entry.client_name}</span>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="font-medium text-rose-600 hover:text-rose-700"
                    >
                      Remove
                    </button>
                  </div>
                  <div class="h-2 overflow-hidden rounded-full bg-zinc-100">
                    <div
                      class="h-full rounded-full bg-emerald-500 transition-all"
                      style={"width: #{entry.progress}%"}
                    >
                    </div>
                  </div>
                  <p
                    :for={err <- upload_errors(@uploads.signature, entry)}
                    class="text-sm text-rose-600"
                  >
                    {upload_error_to_string(err)}
                  </p>
                </div>
              </div>

              <:actions>
                <.button phx-disable-with="Saving...">Save certificate settings</.button>
              </:actions>
            </.simple_form>

            <button
              type="button"
              phx-click="test_pdf"
              disabled={@generating_pdf?}
              class="mt-4 inline-flex items-center gap-2 rounded-full border border-dark px-5 py-2.5 text-sm font-medium text-dark transition hover:bg-dark hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
              {if @generating_pdf?, do: "Generating…", else: "Test PDF"}
            </button>
          </section>

          <section class="rounded-3xl border border-black/5 bg-white p-3">
            <p class="mb-2 px-3 pt-1 text-sm font-semibold text-dark">Live preview</p>
            <iframe
              srcdoc={@preview_html}
              title="Certificate preview"
              class="aspect-video w-full rounded-xl border border-black/5"
            >
            </iframe>
          </section>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp assign_preview(socket) do
    changeset = socket.assigns.form.source
    signature_url = current_signature_url(socket, changeset)

    socket
    |> assign(:signature_url, signature_url)
    |> assign(
      :preview_html,
      Template.render_html(sample_assigns(socket, changeset, signature_url))
    )
  end

  defp sample_assigns(socket) do
    changeset = socket.assigns.form.source
    sample_assigns(socket, changeset, current_signature_url(socket, changeset))
  end

  defp sample_assigns(socket, changeset, signature_url) do
    %{
      learner_name: "Jane Sample",
      title: socket.assigns.course.title,
      type_label: "Course Achievement",
      issued_on: Calendar.strftime(Date.utc_today(), "%B %-d, %Y"),
      serial_number: @sample_serial_number,
      issuer_name: get_field(changeset, :certificate_issuer_name) || "Wasomi Business Institute",
      signatory_name: get_field(changeset, :certificate_signatory_name),
      signatory_title: get_field(changeset, :certificate_signatory_title),
      signature_url: signature_url
    }
  end

  defp current_signature_url(socket, changeset) do
    pending_signature_url(socket) || get_field(changeset, :certificate_signature_key)
  end

  defp pending_signature_url(socket) do
    uploads = socket.assigns.uploads.signature

    uploads.entries
    |> Enum.find(& &1.done?)
    |> case do
      nil -> nil
      entry -> get_in(uploads.entry_refs_to_metas, [entry.ref, :public_url])
    end
  end

  defp get_field(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp consume_signature_upload(socket) do
    case consume_uploaded_entries(socket, :signature, fn meta, _entry ->
           {:ok, meta.public_url}
         end) do
      [url] when is_binary(url) -> {:ok, url}
      # The file uploaded to R2 fine, but Storage.R2 couldn't compute a
      # public_url (R2_PUBLIC_URL not configured) — surface this instead of
      # silently saving without a signature.
      [nil] -> {:error, :missing_public_url}
      [] -> :no_upload
    end
  end

  defp presign_entry(entry, socket, course_id) do
    attrs = %{
      "filename" => entry.client_name,
      "content_type" => entry.client_type,
      "size" => entry.client_size,
      "prefix" => "certificates/#{course_id}"
    }

    with :ok <- validate_png(entry.client_name, entry.client_type),
         {:ok, upload} <- Storage.presign_upload(socket.assigns.current_user, attrs) do
      {:ok,
       %{
         uploader: "R2",
         url: upload.url,
         key: upload.key,
         public_url: upload.public_url,
         content_type: upload.content_type
       }, socket}
    else
      {:error, reason} -> {:error, %{reason: upload_error_to_string(reason)}, socket}
    end
  end

  defp validate_png(filename, content_type) do
    extension_ok? = filename |> Path.extname() |> String.downcase() == ".png"
    type_ok? = content_type in [nil, "", "image/png", "application/octet-stream"]

    if extension_ok? and type_ok?, do: :ok, else: {:error, :not_accepted}
  end

  defp renderer, do: Application.fetch_env!(:wasomi, :certificate_renderer)

  defp upload_error_to_string(:too_large), do: "That image is larger than the 2 MB limit."
  defp upload_error_to_string(:not_accepted), do: "Please choose a transparent PNG image."
  defp upload_error_to_string(:too_many_files), do: "You can only attach one signature image."
  defp upload_error_to_string(:image_too_large), do: "That image is larger than the 2 MB limit."
  defp upload_error_to_string(message) when is_binary(message), do: message
  defp upload_error_to_string(_), do: "Could not accept that image."
end
