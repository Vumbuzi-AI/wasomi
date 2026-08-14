defmodule WasomiWeb.CourseLive.FormComponent do
  use WasomiWeb, :live_component

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS
  alias Wasomi.{Catalog, Learning}
  alias Wasomi.Catalog.PublishGuard

  @max_thumbnail_bytes 5_000_000

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage course records in your database.</:subtitle>
      </.header>

      <div :if={@course.id} class="mt-6 flex flex-wrap items-center gap-3">
        <span class="text-sm font-medium text-muted">Status</span>
        <.status_badge status={@course.status} />

        <div class="ml-auto flex items-center gap-3">
          <button
            :if={@course.status == :draft}
            type="button"
            phx-click="publish_course"
            phx-target={@myself}
            class="rounded-full bg-dark px-4 py-2 text-sm font-medium text-white transition hover:bg-primary"
          >
            Publish course
          </button>

          <button
            :if={@course.status == :published}
            type="button"
            phx-click="unpublish_course"
            phx-target={@myself}
            class="rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-primary hover:text-primary"
          >
            Unpublish
          </button>

          <button
            :if={@course.status == :published}
            type="button"
            phx-click="confirm_archive_course"
            phx-target={@myself}
            class="rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-red-400 hover:text-red-500"
          >
            Archive
          </button>
        </div>
      </div>

      <div :if={@publish_checklist}>
        <p class="mt-4 text-sm font-semibold text-dark">This course isn't ready to publish yet:</p>
        <.publish_checklist stages={@publish_checklist} />
      </div>

      <.confirm_modal
        :if={@confirming_archive?}
        id="archive-course-modal"
        title={"Archive \"#{@course.title}\"?"}
        confirm_label="Archive"
        confirm={JS.push("archive_course", target: @myself)}
        cancel={JS.push("cancel_archive_course", target: @myself)}
      >
        {archive_confirmation_copy(@incomplete_enrollee_count)}
      </.confirm_modal>

      <.simple_form
        for={@form}
        id="course-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        novalidate
      >
        <.input :if={@action == :edit} field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:description]} type="textarea" label="Description" rows="5" />
        <div class="hidden">
          <.input field={@form[:thumbnail_key]} type="text" />
        </div>

        <div class="space-y-2">
          <span class="block text-sm font-semibold text-zinc-800">Upload thumbnail</span>

          <label
            phx-drop-target={@uploads.thumbnail.ref}
            class="group relative flex min-h-[160px] w-full cursor-pointer flex-col items-center justify-center overflow-hidden rounded-xl border border-dashed border-zinc-300 bg-zinc-50 p-3 transition hover:border-zinc-400 hover:bg-zinc-100/50"
          >
            <.live_file_input upload={@uploads.thumbnail} class="sr-only" />

            <%= cond do %>
              <% entry = List.first(@uploads.thumbnail.entries) -> %>
                <div class="relative h-44 w-full overflow-hidden rounded-lg bg-zinc-100">
                  <.live_img_preview entry={entry} class="h-full w-full object-cover" />
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-target={@myself}
                    phx-value-ref={entry.ref}
                    class="absolute top-2 right-2 z-10 rounded-full bg-black/70 p-1.5 text-white transition hover:bg-rose-600"
                    title="Remove thumbnail"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </div>
              <% thumbnail_preview(@form[:thumbnail_key].value) -> %>
                <div class="relative h-44 w-full overflow-hidden rounded-lg bg-zinc-100">
                  <img
                    src={thumbnail_preview(@form[:thumbnail_key].value)}
                    alt=""
                    class="h-full w-full object-cover"
                  />
                </div>
              <% true -> %>
                <div class="flex flex-col items-center justify-center py-4 text-center">
                  <.icon name="hero-photo" class="h-8 w-8 text-zinc-400" />
                  <p class="mt-2 text-sm font-medium text-zinc-700">
                    Click to select photo or drag and drop
                  </p>
                  <p class="mt-1 text-xs text-zinc-500">
                    JPG, PNG, WebP, GIF or SVG, up to 5 MB
                  </p>
                </div>
            <% end %>
          </label>

          <div :for={entry <- @uploads.thumbnail.entries} class="space-y-1">
            <div :if={entry.progress > 0} class="h-2 overflow-hidden rounded-full bg-zinc-100">
              <div
                class="h-full rounded-full bg-dark transition-all"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
            <p
              :for={err <- upload_errors(@uploads.thumbnail, entry)}
              class="text-sm font-medium text-rose-600"
            >
              {upload_error_to_string(err)}
            </p>
          </div>
        </div>

        <.input field={@form[:is_free]} type="checkbox" label="This course is free" />

        <div :if={not free_course?(@form)} class="space-y-2">
          <.input
            field={@form[:price_minor]}
            type="number"
            label="Price"
            value={price_input_value(assigns)}
            min="0"
            step="0.01"
            placeholder="15000.00"
          />
          <p class="text-xs text-zinc-500">
            Enter the full amount, e.g. 15000.00 {@form[:currency].value || "KES"}.
          </p>
        </div>

        <.input field={@form[:currency]} type="text" label="Currency" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Course</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{course: course} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign(:price_input, nil)
      |> assign(:publish_checklist, nil)
      |> assign(:confirming_archive?, false)
      |> assign(:incomplete_enrollee_count, 0)
      |> assign_new(:form, fn ->
        to_form(Catalog.change_course(course))
      end)

    socket =
      if socket.assigns[:uploads] do
        socket
      else
        allow_upload(socket, :thumbnail,
          accept: ~w(.jpg .jpeg .png .webp .gif .svg),
          max_entries: 1,
          max_file_size: @max_thumbnail_bytes
        )
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"course" => course_params}, socket) do
    changeset =
      socket.assigns.course
      |> Catalog.change_course(normalize_price_params(course_params))

    {:noreply,
     assign(socket,
       form: to_form(changeset, action: :validate),
       price_input: raw_price_input(course_params)
     )}
  end

  def handle_event("save", %{"course" => course_params}, socket) do
    course_params = put_uploaded_thumbnail(socket, course_params)

    save_course(
      socket,
      socket.assigns.action,
      normalize_price_params(course_params),
      course_params
    )
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :thumbnail, ref)}
  end

  def handle_event("publish_course", _params, socket) do
    case Catalog.publish_course(socket.assigns.course) do
      {:ok, course} ->
        notify_parent({:saved, course})

        {:noreply,
         socket
         |> put_flash(:info, "Course published — it's now visible in the public catalog.")
         |> assign(course: course, publish_checklist: nil)
         |> push_patch(to: socket.assigns.patch.(course))}

      {:error, issues} when is_list(issues) ->
        checklist =
          socket.assigns.course.id
          |> Catalog.get_course_with_outline!()
          |> PublishGuard.checklist()

        {:noreply, assign(socket, :publish_checklist, checklist)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Could not publish this course.")}
    end
  end

  def handle_event("unpublish_course", _params, socket) do
    {:ok, course} = Catalog.unpublish_course(socket.assigns.course)
    notify_parent({:saved, course})

    {:noreply,
     socket
     |> put_flash(:info, "Course unpublished — it's no longer visible in the public catalog.")
     |> assign(course: course)
     |> push_patch(to: socket.assigns.patch.(course))}
  end

  def handle_event("confirm_archive_course", _params, socket) do
    count = Learning.count_incomplete_enrollees(socket.assigns.course)
    {:noreply, assign(socket, confirming_archive?: true, incomplete_enrollee_count: count)}
  end

  def handle_event("cancel_archive_course", _params, socket) do
    {:noreply, assign(socket, :confirming_archive?, false)}
  end

  def handle_event("archive_course", _params, socket) do
    {:ok, course} = Catalog.archive_course(socket.assigns.course)
    notify_parent({:saved, course})

    {:noreply,
     socket
     |> put_flash(:info, "Course archived — it's no longer visible in the public catalog.")
     |> assign(course: course, confirming_archive?: false)
     |> push_patch(to: socket.assigns.patch.(course))}
  end

  defp put_uploaded_thumbnail(socket, params) do
    uploaded =
      consume_uploaded_entries(socket, :thumbnail, fn %{path: tmp_path}, entry ->
        dir = Path.join(:code.priv_dir(:wasomi), "static/uploads/thumbnails")
        File.mkdir_p!(dir)
        filename = "#{entry.uuid}#{entry.client_name |> Path.extname() |> String.downcase()}"
        File.cp!(tmp_path, Path.join(dir, filename))
        {:ok, "/uploads/thumbnails/#{filename}"}
      end)

    case uploaded do
      [url | _] -> Map.put(params, "thumbnail_key", url)
      [] -> params
    end
  end

  defp save_course(socket, :edit, course_params, raw_course_params) do
    case Catalog.update_course(socket.assigns.course, course_params) do
      {:ok, course} ->
        notify_parent({:saved, course})

        {:noreply,
         socket
         |> put_flash(:info, "Course updated successfully")
         |> push_patch(to: socket.assigns.patch.(course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset), price_input: raw_price_input(raw_course_params))}
    end
  end

  defp save_course(socket, :new, course_params, raw_course_params) do
    case Catalog.create_course(course_params) do
      {:ok, course} ->
        notify_parent({:saved, course})

        {:noreply,
         socket
         |> put_flash(:info, "Course created successfully")
         |> push_patch(to: socket.assigns.patch.(course))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset), price_input: raw_price_input(raw_course_params))}
    end
  end

  defp free_course?(form) do
    Form.normalize_value("checkbox", form[:is_free].value)
  end

  defp normalize_price_params(params) do
    params = Map.new(params)

    is_free =
      case params do
        %{"is_free" => val} -> val in ["true", true, "1", 1]
        %{is_free: val} -> val in ["true", true, "1", 1]
        _ -> false
      end

    if is_free do
      if Enum.any?(Map.keys(params), &is_atom/1) do
        Map.put(params, :price_minor, nil)
      else
        Map.put(params, "price_minor", nil)
      end
    else
      cond do
        Map.has_key?(params, "price_minor") ->
          Map.update!(params, "price_minor", &major_to_minor/1)

        Map.has_key?(params, :price_minor) ->
          Map.update!(params, :price_minor, &major_to_minor/1)

        true ->
          params
      end
    end
  end

  defp raw_price_input(%{"price_minor" => price}), do: price
  defp raw_price_input(%{price_minor: price}), do: price
  defp raw_price_input(_params), do: nil

  defp major_to_minor(value) when is_integer(value), do: value * 100

  defp major_to_minor(value) when is_binary(value) do
    trimmed = String.trim(value)

    with false <- trimmed == "",
         {major, ""} <- Decimal.parse(trimmed),
         minor <- Decimal.mult(major, Decimal.new(100)),
         rounded_minor <- Decimal.round(minor, 0),
         true <- Decimal.equal?(minor, rounded_minor) do
      rounded_minor
      |> Decimal.to_integer()
      |> Integer.to_string()
    else
      true -> ""
      _ -> value
    end
  end

  defp major_to_minor(value), do: value

  defp price_input_value(%{price_input: price}) when not is_nil(price), do: price
  defp price_input_value(%{form: form}), do: minor_to_major(form[:price_minor].value)

  defp minor_to_major(value) when is_integer(value), do: format_minor_as_major(value)

  defp minor_to_major(value) when is_binary(value) do
    case Integer.parse(value) do
      {minor, ""} -> format_minor_as_major(minor)
      _ -> value
    end
  end

  defp minor_to_major(value), do: value

  defp format_minor_as_major(value) do
    sign = if value < 0, do: "-", else: ""
    value = abs(value)
    cents = value |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{sign}#{div(value, 100)}.#{cents}"
  end

  defp thumbnail_preview(value) when is_binary(value) and value != "", do: value
  defp thumbnail_preview(_value), do: nil

  defp upload_error_to_string(:too_large), do: "That image is larger than the 5 MB limit."

  defp upload_error_to_string(:not_accepted),
    do: "Please choose a JPG, PNG, WebP, GIF or SVG image."

  defp upload_error_to_string(:too_many_files), do: "You can only attach one thumbnail."
  defp upload_error_to_string(_), do: "Could not accept that image."

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
