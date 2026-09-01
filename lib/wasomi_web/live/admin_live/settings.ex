defmodule WasomiWeb.AdminLive.Settings do
  @moduledoc """
  Account settings for administrators: manage personal profile (avatar picture,
  name, role/title, bio, phone) as well as the sign-in email and password.
  """

  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Storage}

  @max_avatar_bytes 2_000_000
  @avatar_failed_msg "That picture couldn't be uploaded, so it wasn't saved. " <>
                       "Your other changes were saved — please try the picture again."

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok -> put_flash(socket, :info, "Email changed successfully.")
        :error -> put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/admin/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile_changeset = Accounts.change_user_profile(user)

    socket =
      socket
      |> assign(:page_title, "Account settings")
      |> assign(:settings_tab, :profile)
      |> assign(:current_email, user.email)
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:trigger_submit, false)
      |> assign(:profile_form, to_form(profile_changeset))
      |> assign(:profile_dirty, false)
      |> assign(:email_form, to_form(Accounts.change_user_email(user)))
      |> assign(:password_form, to_form(Accounts.change_user_password(user)))
      |> allow_upload(:avatar,
        accept: ~w(.png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: @max_avatar_bytes,
        auto_upload: true,
        external: &presign_avatar_entry(&1, &2, user),
        progress: &handle_avatar_progress/3
      )
      |> assign_avatar_url()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :settings_tab, settings_tab(params["section"]))}
  end

  def handle_event("validate_profile", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:profile_form, to_form(changeset))
     |> assign_avatar_url()
     |> assign_profile_dirty()}
  end

  def handle_event("save_profile", %{"user" => user_params}, socket) do
    case merge_avatar_upload(socket, user_params) do
      {:ok, socket, user_params} ->
        save_profile(socket, user_params)

      {:error, socket, :missing_public_url} ->
        {:noreply, missing_public_url_flash(socket)}
    end
  end

  def handle_event("remove-avatar", _params, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_profile(%{"avatar_key" => nil})
      |> Map.put(:action, :validate)

    socket =
      Enum.reduce(socket.assigns.uploads.avatar.entries, socket, fn entry, socket ->
        cancel_upload(socket, :avatar, entry.ref)
      end)

    {:noreply,
     socket
     |> assign(:profile_form, to_form(changeset))
     |> assign_avatar_url()
     |> assign_profile_dirty()}
  end

  def handle_event("cancel-avatar-upload", %{"ref" => ref}, socket) do
    {:noreply,
     socket |> cancel_upload(:avatar, ref) |> assign_avatar_url() |> assign_profile_dirty()}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/admin/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_avatar_progress(:avatar, entry, socket) do
    if entry.done?,
      do: {:noreply, socket |> assign_avatar_url() |> assign_profile_dirty()},
      else: {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <.admin_layout active={:settings} current_user={@current_user}>
      <div class="mx-auto max-w-6xl px-5 py-8 lg:px-8">
        <.page_header eyebrow="Settings" title="Account settings">
          <:subtitle>
            Manage your personal profile, email and password credentials.
          </:subtitle>
        </.page_header>

        <div class="mt-8 grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)] lg:items-start">
          <nav
            aria-label="Account settings sections"
            class="rounded-3xl border border-black/5 bg-white p-3 shadow-card"
          >
            <.link
              patch={~p"/admin/settings?section=profile"}
              class={settings_nav_class(@settings_tab, :profile)}
            >
              <.icon name="hero-identification" class="h-5 w-5" /> Profile
            </.link>
            <.link
              patch={~p"/admin/settings?section=security"}
              class={settings_nav_class(@settings_tab, :security)}
            >
              <.icon name="hero-shield-check" class="h-5 w-5" /> Account & Security
            </.link>
          </nav>

          <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8">
            <%!-- Profile Panel --%>
            <section id="settings-profile-panel" class={settings_panel_class(@settings_tab, :profile)}>
              <div>
                <h2 class="text-2xl font-semibold text-ink">Profile basics</h2>
                <p class="mt-2 max-w-2xl text-sm text-body">
                  Your name and profile picture appear in cohort discussions, announcements, and administrative records.
                </p>
              </div>

              <.form
                for={@profile_form}
                id="profile_form"
                phx-submit="save_profile"
                phx-change="validate_profile"
                class="mt-8 max-w-2xl space-y-8"
              >
                <.avatar_upload upload={@uploads.avatar} current_url={@avatar_url} />

                <div class="hidden">
                  <.input field={@profile_form[:avatar_key]} type="text" />
                </div>

                <div class="space-y-6">
                  <div class="grid gap-6 sm:grid-cols-2">
                    <.input
                      field={@profile_form[:first_name]}
                      type="text"
                      label="First name"
                      required
                    />
                    <.input field={@profile_form[:last_name]} type="text" label="Last name" required />
                  </div>

                  <.input
                    field={@profile_form[:headline]}
                    type="text"
                    label="Headline"
                    placeholder="A short headline — e.g. Lead Instructor, Curriculum Lead"
                  />

                  <.input
                    field={@profile_form[:phone]}
                    type="tel"
                    label="Phone number"
                    placeholder="+254 712 345 678"
                  />

                  <.input
                    field={@profile_form[:bio]}
                    type="textarea"
                    label="Bio"
                    placeholder="A short introduction — up to 500 characters."
                    rows="3"
                  />
                </div>

                <div class="flex items-center gap-4">
                  <.button
                    phx-disable-with="Saving..."
                    class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-ink"
                  >
                    Save profile
                  </.button>
                </div>
              </.form>
            </section>

            <%!-- Security Panel --%>
            <section
              id="settings-security-panel"
              class={settings_panel_class(@settings_tab, :security)}
            >
              <div>
                <h2 class="text-2xl font-semibold text-ink">Login & credentials</h2>
                <p class="mt-2 max-w-2xl text-sm text-body">
                  Manage your email address and password credentials.
                </p>
              </div>

              <div class="mt-8 max-w-2xl space-y-10">
                <div>
                  <h3 class="text-base font-semibold text-ink">Email address</h3>
                  <p class="mt-1 text-sm text-body">
                    Changing your email sends a confirmation link to the new address.
                  </p>

                  <.form
                    for={@email_form}
                    id="email_form"
                    phx-submit="update_email"
                    phx-change="validate_email"
                    class="mt-4 space-y-6"
                  >
                    <.input field={@email_form[:email]} type="email" label="Email" required />
                    <.input
                      field={@email_form[:current_password]}
                      name="current_password"
                      id="current_password_for_email"
                      type="password"
                      label="Current password"
                      value={@email_form_current_password}
                      required
                    />
                    <.button phx-disable-with="Changing..." class="rounded-full bg-ink px-5">
                      Change Email
                    </.button>
                  </.form>
                </div>

                <hr class="border-black/5" />

                <div>
                  <h3 class="text-base font-semibold text-ink">Password</h3>
                  <p class="mt-1 text-sm text-body">
                    Use a strong password and confirm the change with your current one.
                  </p>

                  <.form
                    for={@password_form}
                    id="password_form"
                    action={~p"/users/log_in?_action=admin_password_updated"}
                    method="post"
                    phx-change="validate_password"
                    phx-submit="update_password"
                    phx-trigger-action={@trigger_submit}
                    class="mt-4 space-y-6"
                  >
                    <input
                      name={@password_form[:email].name}
                      type="hidden"
                      id="hidden_user_email"
                      value={@current_email}
                    />
                    <.input
                      field={@password_form[:password]}
                      type="password"
                      label="New password"
                      required
                    />
                    <.input
                      field={@password_form[:password_confirmation]}
                      type="password"
                      label="Confirm new password"
                    />
                    <.input
                      field={@password_form[:current_password]}
                      name="current_password"
                      type="password"
                      label="Current password"
                      id="current_password_for_password"
                      value={@current_password}
                      required
                    />
                    <.button phx-disable-with="Changing..." class="rounded-full bg-ink px-5">
                      Change Password
                    </.button>
                  </.form>
                </div>
              </div>
            </section>
          </div>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp settings_nav_class(active_tab, tab) do
    [
      "flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-left text-sm font-semibold transition",
      active_tab == tab && "bg-primary text-white shadow-sm",
      active_tab != tab && "text-body hover:bg-surface"
    ]
  end

  defp settings_panel_class(active_tab, tab) do
    if active_tab == tab, do: "block", else: "hidden"
  end

  defp settings_tab("security"), do: :security
  defp settings_tab(_), do: :profile

  defp avatar_upload(assigns) do
    has_image? = assigns.current_url != nil || assigns.upload.entries != []
    assigns = assign(assigns, has_image?: has_image?, max_bytes: @max_avatar_bytes)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-center gap-6">
        <div class="grid h-24 w-24 shrink-0 place-items-center overflow-hidden rounded-full border-2 border-black/5 bg-surface shadow-sm sm:h-28 sm:w-28">
          <%= if entry = List.first(@upload.entries) do %>
            <%= if entry.done? && @current_url do %>
              <img
                id="avatar-preview-uploaded"
                phx-hook="ImageRetry"
                src={@current_url}
                alt="Avatar preview"
                class="h-full w-full object-cover"
              />
            <% else %>
              <.live_img_preview
                entry={entry}
                alt="Avatar preview"
                class="h-full w-full object-cover"
              />
            <% end %>
          <% else %>
            <%= if @current_url do %>
              <img
                id="avatar-preview-current"
                phx-hook="ImageRetry"
                src={@current_url}
                alt="Avatar preview"
                class="h-full w-full object-cover"
              />
            <% else %>
              <div class="grid place-items-center text-muted">
                <.icon name="hero-user" class="h-12 w-12" />
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="flex flex-col items-start gap-2">
          <div
            id="avatar-upload-processor"
            phx-hook="ImageUploadProcessor"
            phx-update="ignore"
            data-aspect-ratio="1"
            data-crop-title="Crop your profile picture"
            data-live-input={@upload.ref}
            data-max-bytes={@max_bytes}
          >
            <label class="inline-flex cursor-pointer items-center justify-center rounded-xl bg-ink px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:bg-primary">
              <span>{if @has_image?, do: "Change picture", else: "Upload picture"}</span>
              <input
                type="file"
                data-role="picker"
                accept="image/png,image/jpeg,image/webp"
                class="sr-only"
              />
            </label>
          </div>
          <.live_file_input upload={@upload} class="hidden" />

          <%= if entry = List.first(@upload.entries) do %>
            <button
              type="button"
              phx-click="cancel-avatar-upload"
              phx-value-ref={entry.ref}
              class="inline-flex cursor-pointer items-center justify-center rounded-xl border border-black/10 bg-white px-4 py-1.5 text-xs font-medium text-body transition hover:border-rose-200 hover:bg-rose-50 hover:text-rose-600"
            >
              Delete picture
            </button>
          <% else %>
            <%= if @current_url do %>
              <button
                type="button"
                phx-click="remove-avatar"
                class="inline-flex cursor-pointer items-center justify-center rounded-xl border border-black/10 bg-white px-4 py-1.5 text-xs font-medium text-body transition hover:border-rose-200 hover:bg-rose-50 hover:text-rose-600"
              >
                Delete picture
              </button>
            <% else %>
              <p class="text-xs text-muted">PNG, JPG or WEBP up to 2 MB.</p>
            <% end %>
          <% end %>

          <p :if={@has_image?} class="text-xs text-muted">PNG, JPG or WEBP up to 2 MB.</p>
        </div>
      </div>

      <%= for err <- upload_errors(@upload) do %>
        <p class="text-xs text-rose-600">
          {avatar_upload_error_to_string(err)}
        </p>
      <% end %>
    </div>
    """
  end

  defp save_profile(socket, user_params) do
    case Accounts.update_user_profile(socket.assigns.current_user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile saved successfully.")
         |> assign(:current_user, user)
         |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
         |> assign(:profile_dirty, false)
         |> assign_avatar_url()}

      {:error, changeset} ->
        {:noreply, socket |> assign(:profile_form, to_form(changeset)) |> assign_profile_dirty()}
    end
  end

  defp assign_profile_dirty(socket) do
    changeset = socket.assigns.profile_form.source
    dirty? = changeset.changes != %{} or socket.assigns.uploads.avatar.entries != []
    assign(socket, :profile_dirty, dirty?)
  end

  defp missing_public_url_flash(socket) do
    put_flash(
      socket,
      :error,
      "The avatar uploaded, but no public storage URL is configured (R2_PUBLIC_URL). " <>
        "Nothing was saved — ask an engineer to set it, then re-upload."
    )
  end

  defp assign_avatar_url(socket) do
    changeset = socket.assigns.profile_form.source
    assign(socket, :avatar_url, current_avatar_url(socket, changeset))
  end

  defp current_avatar_url(socket, changeset) do
    pending_avatar_url(socket) || Ecto.Changeset.get_field(changeset, :avatar_key)
  end

  defp pending_avatar_url(socket) do
    uploads = socket.assigns.uploads.avatar

    uploads.entries
    |> Enum.find(& &1.done?)
    |> case do
      nil -> nil
      entry -> get_in(uploads.entry_refs_to_metas, [entry.ref, :public_url])
    end
  end

  defp merge_avatar_upload(socket, params) do
    {socket, avatar_failed?} = drop_incomplete_avatar_entries(socket)

    case consume_avatar_upload(socket) do
      {:ok, url} ->
        {:ok, socket, Map.put(params, "avatar_key", url)}

      :no_upload when avatar_failed? ->
        {:ok, put_flash(socket, :error, @avatar_failed_msg), params}

      :no_upload ->
        {:ok, socket, params}

      {:error, :missing_public_url} ->
        {:error, socket, :missing_public_url}
    end
  end

  defp drop_incomplete_avatar_entries(socket) do
    case uploaded_entries(socket, :avatar) do
      {_done, []} ->
        {socket, false}

      {_done, [_ | _] = incomplete} ->
        {Enum.reduce(incomplete, socket, &cancel_upload(&2, :avatar, &1.ref)), true}
    end
  end

  defp consume_avatar_upload(socket) do
    case consume_uploaded_entries(socket, :avatar, fn meta, _entry -> {:ok, meta.public_url} end) do
      [url] when is_binary(url) -> {:ok, url}
      [nil] -> {:error, :missing_public_url}
      [] -> :no_upload
    end
  end

  defp presign_avatar_entry(entry, socket, user) do
    attrs = %{
      "filename" => entry.client_name,
      "content_type" => entry.client_type,
      "size" => entry.client_size
    }

    with :ok <- validate_image(entry.client_name, entry.client_type),
         {:ok, upload} <- Storage.presign_avatar_upload(user, attrs) do
      {:ok,
       %{
         uploader: "R2",
         url: upload.url,
         key: upload.key,
         public_url: upload.public_url,
         content_type: upload.content_type
       }, socket}
    else
      {:error, reason} -> {:error, %{reason: avatar_upload_error_to_string(reason)}, socket}
    end
  end

  defp validate_image(filename, content_type) do
    extension = filename |> Path.extname() |> String.downcase()
    extension_ok? = extension in [".png", ".jpg", ".jpeg", ".webp"]

    type_ok? =
      content_type in [
        nil,
        "",
        "image/png",
        "image/jpeg",
        "image/webp",
        "application/octet-stream"
      ]

    if extension_ok? and type_ok?, do: :ok, else: {:error, :not_accepted}
  end

  defp avatar_upload_error_to_string(:too_large), do: "Image is too large (max 2 MB)."

  defp avatar_upload_error_to_string(:not_accepted),
    do: "Please select a PNG, JPG, or WEBP image."

  defp avatar_upload_error_to_string(:too_many_files), do: "You can only upload one picture."
  defp avatar_upload_error_to_string(_), do: "Could not upload image. Please try another."
end
