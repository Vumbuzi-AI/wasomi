defmodule WasomiWeb.CourseLive.FormComponent do
  use WasomiWeb, :live_component

  alias Wasomi.Catalog

  @max_thumbnail_bytes 5_000_000

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage course records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="course-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:subtitle]} type="text" label="Subtitle" />
        <.input field={@form[:description]} type="textarea" label="Description" rows="5" />
        <.input field={@form[:thumbnail_key]} type="text" label="Thumbnail key" />

        <div class="space-y-3">
          <span class="block text-sm font-semibold leading-6 text-zinc-800">Upload thumbnail</span>

          <img
            :if={thumbnail_preview(@form[:thumbnail_key].value)}
            src={thumbnail_preview(@form[:thumbnail_key].value)}
            alt=""
            class="h-40 w-full rounded-lg border border-zinc-200 object-cover"
          />

          <.live_file_input upload={@uploads.thumbnail} class="block w-full text-sm text-zinc-700" />

          <p class="text-xs text-zinc-500">
            JPG, PNG, WebP, GIF or SVG, up to 5 MB.
          </p>

          <div :for={entry <- @uploads.thumbnail.entries} class="space-y-1">
            <div class="flex items-center justify-between gap-3 text-sm text-zinc-700">
              <span>{entry.client_name}</span>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-target={@myself}
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
            <p :for={err <- upload_errors(@uploads.thumbnail, entry)} class="text-sm text-rose-600">
              {upload_error_to_string(err)}
            </p>
          </div>
        </div>

        <div class="space-y-2">
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
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          prompt="Choose a value"
          options={Ecto.Enum.values(Wasomi.Catalog.Course, :status)}
        />
        <.input field={@form[:position]} type="number" label="Position" />
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
         |> push_patch(to: socket.assigns.patch)}

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
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, form: to_form(changeset), price_input: raw_price_input(raw_course_params))}
    end
  end

  defp normalize_price_params(params) do
    params = Map.new(params)

    cond do
      Map.has_key?(params, "price_minor") -> Map.update!(params, "price_minor", &major_to_minor/1)
      Map.has_key?(params, :price_minor) -> Map.update!(params, :price_minor, &major_to_minor/1)
      true -> params
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
