defmodule WasomiWeb.AdminLive.LandingImages do
  @moduledoc """
  Admin editor for landing-page images: one card per slot (thumbnail, label,
  default/custom status, Edit), no replica of the public page itself. Edit
  opens a focused modal with upload, live preview, alt text, and reset.
  """

  use WasomiWeb, :live_view

  alias Wasomi.{Content, Storage}
  alias Wasomi.Content.{LandingImage, LandingPreview}

  # Hero/step imagery is full-bleed marketing photography, not a small
  # signature graphic — 5 MB comfortably fits a high-quality PNG at the
  # sizes these slots render at, while staying well under the 10 MB hard
  # ceiling enforced in `Wasomi.Storage.R2`.
  @max_image_bytes 5_000_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Enum.reduce(LandingImage.slots(), socket, fn slot, socket ->
        allow_upload(socket, slot,
          accept: ~w(.png),
          max_entries: 1,
          max_file_size: @max_image_bytes,
          auto_upload: true,
          external: &presign_entry(&1, &2, slot),
          progress: &handle_progress/3
        )
      end)

    {:ok,
     socket
     |> assign(:page_title, "Landing page images")
     |> assign(:editing_slot, nil)
     |> assign_slots()}
  end

  @impl true
  def handle_event("open-edit", %{"slot" => slot}, socket) do
    {:noreply, assign(socket, :editing_slot, slot_atom(slot))}
  end

  def handle_event("close-edit", _params, socket) do
    {:noreply,
     socket
     |> discard_pending_upload(socket.assigns.editing_slot)
     |> assign(:editing_slot, nil)
     |> assign_slots()}
  end

  # Fires when a file is picked (auto_upload still routes selection through
  # phx-change) — nothing to validate per slot, the upload progress/errors
  # already re-render via `progress:`.
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref, "slot" => slot}, socket) do
    {:noreply,
     socket
     |> cancel_upload(slot_atom(slot), ref)
     |> assign_slots()}
  end

  def handle_event("save", %{"slot" => slot} = params, socket) do
    slot = slot_atom(slot)
    alt_text = params["alt_text"] |> to_string() |> String.trim()
    alt_text = if alt_text == "", do: nil, else: alt_text

    case consume_upload(socket, slot) do
      {:ok, url} ->
        case Content.put_landing_image(slot, url, alt_text) do
          {:ok, _landing_image} ->
            {:noreply,
             socket
             |> put_flash(:info, "#{LandingImage.label(slot)} updated.")
             |> assign(:editing_slot, nil)
             |> assign_slots()}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, put_flash(socket, :error, "Could not save that image.")}
        end

      :no_upload ->
        slot_info = Map.get(socket.assigns.slots_map, slot)

        if slot_info && slot_info.overridden? do
          case Content.put_landing_image(slot, slot_info.image_url, alt_text) do
            {:ok, _landing_image} ->
              {:noreply,
               socket
               |> put_flash(:info, "#{LandingImage.label(slot)} alt text updated.")
               |> assign(:editing_slot, nil)
               |> assign_slots()}

            {:error, %Ecto.Changeset{}} ->
              {:noreply, put_flash(socket, :error, "Could not update alt text.")}
          end
        else
          {:noreply, assign(socket, :editing_slot, nil)}
        end

      {:error, :missing_public_url} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The image uploaded, but no public storage URL is configured " <>
             "(R2_PUBLIC_URL). Nothing was saved — ask an engineer to set it, then re-upload."
         )}
    end
  end

  def handle_event("reset", %{"slot" => slot}, socket) do
    slot = slot_atom(slot)
    :ok = Content.reset_landing_image(slot)

    {:noreply,
     socket
     |> put_flash(:info, "#{LandingImage.label(slot)} reset to default.")
     |> assign(:editing_slot, nil)
     |> assign_slots()}
  end

  def handle_progress(_upload_name, entry, socket) do
    if entry.done?, do: {:noreply, assign_slots(socket)}, else: {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:landing_images} current_user={@current_user}>
      <div class="w-full space-y-6 px-5 py-8 lg:px-8">
        <.page_header title="Landing page images">
          <:subtitle>
            Override the images shown on the public homepage. Click a card's "Edit" to upload a
            replacement. Anything left untouched keeps its default image.
          </:subtitle>
        </.page_header>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.slot_card :for={slot <- @slots} slot={slot} image={@preview_images[slot.slot]} />
        </div>

        <.slot_edit_modal
          :if={@editing_slot}
          slot_info={@slots_map[@editing_slot]}
          upload={@uploads[@editing_slot]}
          preview_url={@preview_images[@editing_slot].url}
          preview_html={LandingPreview.render_html(@editing_slot, @preview_images)}
        />
      </div>
    </.admin_layout>
    """
  end

  attr :slot, :map, required: true
  attr :image, :map, required: true

  defp slot_card(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-3xl border border-black/5 bg-white shadow-card">
      <img
        id={"slot-thumb-#{@slot.slot}"}
        phx-hook="ImageRetry"
        src={@image.url}
        alt=""
        class="aspect-video w-full object-cover"
      />

      <div class="flex items-center justify-between gap-3 p-4">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-ink">{@slot.label}</p>
          <span class={[
            "mt-1 inline-block rounded-full px-2 py-0.5 text-[10px] font-medium",
            if(@slot.overridden?,
              do: "bg-emerald-100 text-emerald-800",
              else: "bg-zinc-100 text-zinc-600"
            )
          ]}>
            {if @slot.overridden?, do: "Custom", else: "Default"}
          </span>
        </div>

        <button
          id={"edit-slot-#{@slot.slot}-btn"}
          type="button"
          phx-click="open-edit"
          phx-value-slot={@slot.slot}
          class="shrink-0 rounded-full border border-black/10 px-3 py-1.5 text-xs font-semibold text-ink transition hover:bg-surface hover:text-primary"
        >
          Edit
        </button>
      </div>
    </div>
    """
  end

  attr :slot_info, :map, required: true
  attr :upload, :map, required: true
  attr :preview_url, :string, required: true
  attr :preview_html, :string, required: true

  defp slot_edit_modal(assigns) do
    ~H"""
    <.modal id="edit-slot-modal" show on_cancel={JS.push("close-edit")} max_width="max-w-5xl">
      <div
        id={"landing-image-editor-#{@slot_info.slot}"}
        phx-hook="LiveImagePreview"
        class="grid gap-6 lg:grid-cols-2"
      >
        <div class="space-y-5">
          <div class="flex items-start justify-between">
            <div>
              <h2 class="text-lg font-semibold text-ink">{@slot_info.label}</h2>
              <p class="mt-0.5 text-xs text-muted">
                {if @slot_info.overridden?,
                  do: "Currently using a custom image",
                  else: "Currently using the default image"}
              </p>
            </div>
          </div>

          <div class="relative overflow-hidden rounded-2xl border border-black/10 bg-zinc-100">
            <img
              id={"landing-image-preview-img-#{@slot_info.slot}"}
              data-role="preview"
              phx-update="ignore"
              src={@preview_url}
              alt={@slot_info.alt_text}
              class="h-48 w-full object-cover"
            />
            <div class="absolute bottom-2 left-2 rounded-md bg-black/60 px-2 py-1 text-[11px] font-medium text-white backdrop-blur-sm">
              Live Preview
            </div>
          </div>

          <form
            id={"landing-image-#{@slot_info.slot}"}
            phx-change="noop"
            phx-submit="save"
            phx-value-slot={@slot_info.slot}
            class="space-y-4"
          >
            <div>
              <label class="block text-xs font-semibold text-ink">
                Upload new PNG image
              </label>
              <div class="mt-1.5">
                <.live_file_input
                  upload={@upload}
                  class="block w-full text-xs text-zinc-700 file:mr-3 file:rounded-full file:border-0 file:bg-surface file:px-4 file:py-2 file:text-xs file:font-semibold file:text-ink hover:file:bg-neutral-200"
                />
                <p class="mt-1 text-xs text-zinc-500">PNG format only, up to 5 MB.</p>
              </div>
            </div>

            <div
              :for={entry <- @upload.entries}
              class="space-y-1.5 rounded-xl border border-black/5 bg-surface p-3"
            >
              <div class="flex items-center justify-between gap-3 text-xs text-zinc-700">
                <span class="truncate font-medium">{entry.client_name}</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  phx-value-slot={@slot_info.slot}
                  class="shrink-0 font-medium text-rose-600 hover:text-rose-700"
                >
                  Cancel
                </button>
              </div>
              <div class="h-1.5 overflow-hidden rounded-full bg-zinc-200">
                <div
                  class="h-full rounded-full bg-emerald-500 transition-all"
                  style={"width: #{entry.progress}%"}
                >
                </div>
              </div>
              <p :for={err <- upload_errors(@upload, entry)} class="text-xs font-medium text-rose-600">
                {upload_error_to_string(err)}
              </p>
            </div>

            <div>
              <label class="block text-xs font-semibold text-ink">
                Alt text (accessibility description)
                <input
                  type="text"
                  name="alt_text"
                  value={@slot_info.alt_text}
                  maxlength="255"
                  placeholder="Describe the image for screen readers"
                  class="mt-1.5 block w-full rounded-xl border-zinc-200 text-xs focus:border-ink focus:ring-ink"
                />
              </label>
              <p class="mt-1 text-[11px] text-muted">
                Used by screen readers and when images fail to load.
              </p>
            </div>

            <div class="flex flex-col gap-2 pt-2 sm:flex-row-reverse sm:items-center sm:justify-between">
              <div class="flex items-center gap-2">
                <button
                  type="submit"
                  class="w-full sm:w-auto rounded-full bg-ink px-5 py-2.5 text-xs font-semibold text-white shadow-sm transition hover:bg-primary"
                >
                  Save changes
                </button>
                <button
                  type="button"
                  phx-click="close-edit"
                  class="w-full sm:w-auto rounded-full border border-black/10 px-4 py-2.5 text-xs font-semibold text-muted transition hover:bg-surface hover:text-ink"
                >
                  Cancel
                </button>
              </div>

              <button
                :if={@slot_info.overridden?}
                type="button"
                phx-click="reset"
                phx-value-slot={@slot_info.slot}
                class="w-full sm:w-auto rounded-full border border-rose-200 px-4 py-2.5 text-xs font-semibold text-rose-600 transition hover:bg-rose-50"
              >
                Reset to default
              </button>
            </div>
          </form>
        </div>

        <div class="rounded-2xl border border-black/10 bg-zinc-50 p-3">
          <p class="mb-2 px-1 pt-1 text-xs font-semibold text-ink">Preview on homepage</p>
          <%!-- id hashes the preview content on purpose: forces a full
          node replacement on change (fresh mount), not an in-place
          `srcdoc` patch — otherwise ScaledPreview's "load" listener can
          end up attached to a stale/replaced node that never fires. --%>
          <div
            id={"landing-image-scaled-preview-#{@slot_info.slot}-#{:erlang.phash2(@preview_html)}"}
            phx-hook="ScaledPreview"
            class="w-full overflow-hidden rounded-xl border border-black/5 bg-white"
          >
            <iframe srcdoc={@preview_html} title={"#{@slot_info.label} — homepage preview"}></iframe>
          </div>
        </div>
      </div>
    </.modal>
    """
  end

  # Backing out of the modal (Cancel or the X) without saving must also drop
  # any picked-but-unsaved upload — otherwise the entry stays "done" and its
  # object keeps winning in `pending_image_url/1`, leaking the discarded
  # image into the grid thumbnail until the next save/reset.
  defp discard_pending_upload(socket, nil), do: socket

  defp discard_pending_upload(socket, slot) do
    Enum.reduce(socket.assigns.uploads[slot].entries, socket, fn entry, socket ->
      cancel_upload(socket, slot, entry.ref)
    end)
  end

  defp assign_slots(socket) do
    slots = Content.list_landing_image_slots()
    slots_map = Map.new(slots, fn slot -> {slot.slot, slot} end)
    uploads = socket.assigns[:uploads] || %{}

    preview_images =
      Map.new(LandingImage.slots(), fn slot ->
        slot_info = Map.get(slots_map, slot)
        upload = Map.get(uploads, slot)

        url =
          (upload && pending_image_url(upload)) ||
            (slot_info && slot_info.image_url) ||
            LandingImage.default_path(slot)

        alt = (slot_info && slot_info.alt_text) || LandingImage.default_alt(slot)

        {slot, %{url: url, alt: alt}}
      end)

    socket
    |> assign(:slots, slots)
    |> assign(:slots_map, slots_map)
    |> assign(:preview_images, preview_images)
  end

  # Shows the not-yet-saved upload in the preview immediately, same as
  # `CourseCertificate`'s signature preview — an admin sees what they picked
  # before committing to "Save", not just after.
  defp pending_image_url(%{entries: entries, entry_refs_to_metas: metas}) do
    entries
    |> Enum.find(& &1.done?)
    |> case do
      nil -> nil
      entry -> get_in(metas, [entry.ref, :public_url])
    end
  end

  defp pending_image_url(_), do: nil

  defp consume_upload(socket, slot) do
    case consume_uploaded_entries(socket, slot, fn meta, _entry -> {:ok, meta.public_url} end) do
      [url] when is_binary(url) -> {:ok, url}
      [nil] -> {:error, :missing_public_url}
      [] -> :no_upload
    end
  end

  # `@slots` only ever renders known atoms into `phx-value-slot`, so this
  # only ever has to parse a value this page itself produced.
  defp slot_atom(slot) when is_binary(slot), do: String.to_existing_atom(slot)
  defp slot_atom(slot) when is_atom(slot), do: slot

  defp presign_entry(entry, socket, slot) do
    attrs = %{
      "filename" => entry.client_name,
      "content_type" => entry.client_type,
      "size" => entry.client_size,
      "prefix" => "landing/#{slot}",
      "max_image_bytes" => @max_image_bytes
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

  defp upload_error_to_string(:too_large), do: "That image is larger than the 5 MB limit."
  defp upload_error_to_string(:not_accepted), do: "Please choose a PNG image."
  defp upload_error_to_string(:too_many_files), do: "You can only attach one image."
  defp upload_error_to_string(:image_too_large), do: "That image is larger than the 5 MB limit."
  defp upload_error_to_string(message) when is_binary(message), do: message
  defp upload_error_to_string(_), do: "Could not accept that image."
end
