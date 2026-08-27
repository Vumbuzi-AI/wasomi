defmodule WasomiWeb.UserSettingsLive do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Storage}
  alias Wasomi.Accounts.{Countries, User}

  @max_avatar_bytes 2_000_000

  def render(assigns) do
    ~H"""
    <.student_layout active={:account} current_user={@current_user}>
      <div class="mx-auto max-w-6xl px-5 py-10 lg:px-10 lg:py-12">
        <div class="rounded-3xl border border-black/5 bg-white p-6">
          <div>
            <h1 class="text-3xl font-semibold leading-tight text-ink sm:text-4xl">
              Account Settings
            </h1>
            <p class="mt-2 max-w-2xl text-body">
              Manage your profile, learning preferences, email and password.
            </p>
          </div>
        </div>

        <div class="mt-6 grid gap-6 lg:grid-cols-[220px_minmax(0,1fr)] lg:items-start">
          <nav
            aria-label="Account settings sections"
            class="rounded-3xl border border-black/5 bg-white p-3 shadow-card"
          >
            <.link
              patch={~p"/users/settings?section=profile"}
              class={settings_nav_class(@settings_tab, :profile)}
            >
              <.icon name="hero-identification" class="h-5 w-5" /> Profile
            </.link>
            <.link
              patch={~p"/users/settings?section=security"}
              class={settings_nav_class(@settings_tab, :security)}
            >
              <.icon name="hero-shield-check" class="h-5 w-5" /> Account & Security
            </.link>
          </nav>

          <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8">
            <.form
              for={@profile_form}
              id="profile_form"
              phx-submit="save_profile"
              phx-change="validate_profile"
            >
              <section
                id="settings-profile-panel"
                class={settings_panel_class(@settings_tab, :profile)}
              >
                <div>
                  <h2 class="text-2xl font-semibold text-ink">Profile basics</h2>
                  <p class="mt-2 max-w-2xl text-sm text-body">
                    Private to you. No other learner ever sees this. These details help Wasomi personalize your learning experience.
                  </p>
                </div>

                <div class="mt-8 max-w-2xl space-y-8">
                  <.avatar_upload upload={@uploads.avatar} current_url={@avatar_url} />

                  <div class="hidden">
                    <.input field={@profile_form[:avatar_key]} type="text" />
                  </div>

                  <div class="space-y-6">
                    <.input
                      field={@profile_form[:headline]}
                      type="text"
                      label="Headline"
                      placeholder="A short headline — up to 120 characters."
                    />

                    <.input
                      field={@profile_form[:bio]}
                      type="textarea"
                      label="Bio"
                      placeholder="A short introduction — up to 500 characters."
                    />

                    <div class="grid gap-6 sm:grid-cols-2">
                      <.country_combobox field={@profile_form[:country]} />
                      <.input
                        field={@profile_form[:industry]}
                        type="select"
                        label="Industry"
                        prompt="Select an industry"
                        options={User.industries()}
                      />
                    </div>

                    <div class="grid gap-6 sm:grid-cols-2">
                      <.input field={@profile_form[:organization]} type="text" label="Organization" />
                      <.input field={@profile_form[:occupation]} type="text" label="Occupation" />
                    </div>

                    <div class="grid gap-6 sm:grid-cols-2">
                      <.input
                        field={@profile_form[:experience_level]}
                        type="select"
                        label="Experience level"
                        prompt="Select your experience level"
                        options={[
                          {"Student", :student},
                          {"Entry-level", :entry},
                          {"Mid-level", :mid},
                          {"Senior", :senior},
                          {"Lead / Executive", :lead_executive}
                        ]}
                      />
                      <.input
                        field={@profile_form[:learning_goal]}
                        type="select"
                        label="Learning goal"
                        prompt="What brings you to Wasomi?"
                        options={[
                          {"Career advancement", :career_advancement},
                          {"Career switch", :career_switch},
                          {"Certification", :certification},
                          {"Upskilling", :upskilling},
                          {"Personal interest", :personal_interest}
                        ]}
                      />
                    </div>
                  </div>

                  <div class="pt-2">
                    <.button phx-disable-with="Saving..." class="rounded-full bg-ink px-5">
                      Save Profile
                    </.button>
                  </div>
                </div>
              </section>
            </.form>

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
                    action={~p"/users/log_in?_action=password_updated"}
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
    </.student_layout>
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

  attr :field, Phoenix.HTML.FormField, required: true

  # searchable dropdown over Countries.grouped_options/0, filtering client-side via SearchableSelect
  defp country_combobox(assigns) do
    errors = if Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &translate_error/1))
      |> assign(:groups, Countries.grouped_options())

    ~H"""
    <div id={"#{@field.id}-combobox"} phx-hook="SearchableSelect" class="relative">
      <.label for={"#{@field.id}-trigger"}>Country</.label>

      <input type="hidden" name={@field.name} value={@field.value} data-role="value" />

      <button
        type="button"
        id={"#{@field.id}-trigger"}
        data-role="trigger"
        class={[
          "mt-2 flex w-full items-center justify-between rounded-lg px-3 py-2 text-left shadow-sm sm:text-sm sm:leading-6",
          @errors == [] && "border border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border border-rose-400 focus:border-rose-400"
        ]}
      >
        <span data-role="trigger-label" data-placeholder="Select a country" class="text-zinc-900">
          {@field.value || "Select a country"}
        </span>
        <.icon name="hero-chevron-up-down" class="h-4 w-4 shrink-0 text-zinc-400" />
      </button>

      <div
        data-role="panel"
        class="absolute z-20 mt-1 hidden w-full rounded-lg border border-zinc-200 bg-white shadow-lg"
      >
        <div class="p-2">
          <input
            type="text"
            data-role="search"
            placeholder="Search countries…"
            autocomplete="off"
            class="block w-full rounded-md border border-zinc-200 px-3 py-1.5 text-sm text-zinc-900 focus:border-zinc-400 focus:outline-none focus:ring-0"
          />
        </div>
        <div data-role="options" class="max-h-60 overflow-y-auto px-1 pb-2">
          <div :for={{group_label, countries} <- @groups}>
            <p
              data-role="group-label"
              class="px-2 pt-2 pb-1 text-xs font-semibold uppercase tracking-wide text-zinc-400"
            >
              {group_label}
            </p>
            <button
              :for={{country, _country} <- countries}
              type="button"
              data-role="option"
              data-value={country}
              class="block w-full rounded-md px-2 py-1.5 text-left text-sm text-zinc-700 hover:bg-zinc-100"
            >
              {country}
            </button>
          </div>
          <p data-role="empty" class="hidden px-2 py-3 text-center text-sm text-zinc-400">
            No countries match.
          </p>
        </div>
      </div>

      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  attr :upload, :map, required: true
  attr :current_url, :string, default: nil

  defp avatar_upload(assigns) do
    has_image? = assigns.current_url != nil || assigns.upload.entries != []
    assigns = assign(assigns, :has_image?, has_image?)

    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-center gap-6">
        <div class="grid h-28 w-28 shrink-0 place-items-center overflow-hidden rounded-full border-2 border-zinc-100 bg-zinc-50 shadow-sm sm:h-32 sm:w-32">
          <%= if entry = List.first(@upload.entries) do %>
            <%= if entry.done? && @current_url do %>
              <img src={@current_url} alt="Avatar preview" class="h-full w-full object-cover" />
            <% else %>
              <.live_img_preview
                entry={entry}
                alt="Avatar preview"
                class="h-full w-full object-cover"
              />
            <% end %>
          <% else %>
            <%= if @current_url do %>
              <img src={@current_url} alt="Avatar preview" class="h-full w-full object-cover" />
            <% else %>
              <div class="grid place-items-center text-zinc-300">
                <.icon name="hero-user" class="h-14 w-14" />
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="flex flex-col items-start gap-2.5">
          <label class="inline-flex cursor-pointer items-center justify-center rounded-xl bg-ink px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-primary">
            <span>{if @has_image?, do: "Change picture", else: "Upload picture"}</span>
            <.live_file_input upload={@upload} class="sr-only" />
          </label>

          <%= if entry = List.first(@upload.entries) do %>
            <button
              type="button"
              phx-click="cancel-avatar-upload"
              phx-value-ref={entry.ref}
              class="inline-flex cursor-pointer items-center justify-center rounded-xl border border-zinc-200 bg-white px-5 py-2 text-sm font-medium text-zinc-700 transition hover:border-rose-200 hover:bg-rose-50 hover:text-rose-600"
            >
              Delete picture
            </button>
          <% else %>
            <%= if @current_url do %>
              <button
                type="button"
                phx-click="remove-avatar"
                class="inline-flex cursor-pointer items-center justify-center rounded-xl border border-zinc-200 bg-white px-5 py-2 text-sm font-medium text-zinc-700 transition hover:border-rose-200 hover:bg-rose-50 hover:text-rose-600"
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

      <div class="max-w-md space-y-1">
        <p :for={err <- upload_errors(@upload)} class="text-sm font-medium text-rose-600">
          {avatar_upload_error_to_string(err)}
        </p>

        <div :for={entry <- @upload.entries} class="space-y-1">
          <div
            :if={entry.progress > 0 && entry.progress < 100}
            class="h-1.5 overflow-hidden rounded-full bg-zinc-100"
          >
            <div
              class="h-full rounded-full bg-emerald-500 transition-all"
              style={"width: #{entry.progress}%"}
            >
            </div>
          </div>
          <p :for={err <- upload_errors(@upload, entry)} class="text-sm text-rose-600">
            {avatar_upload_error_to_string(err)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    profile_changeset = Accounts.change_user_profile(user)

    socket =
      socket
      |> assign(:page_title, "Account settings")
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:settings_tab, :profile)
      |> assign(:profile_form, to_form(profile_changeset))
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

  def handle_event("set-settings-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :settings_tab, settings_tab(tab))}
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
          &url(~p"/users/settings/confirm_email/#{&1}")
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

  def handle_event("validate_profile", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:profile_form, to_form(changeset)) |> assign_avatar_url()}
  end

  def handle_event("save_profile", %{"user" => user_params}, socket) do
    case merge_avatar_upload(socket, user_params) do
      {:ok, user_params} -> save_profile(socket, user_params)
      {:error, :missing_public_url} -> {:noreply, missing_public_url_flash(socket)}
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

    {:noreply, socket |> assign(:profile_form, to_form(changeset)) |> assign_avatar_url()}
  end

  def handle_event("cancel-avatar-upload", %{"ref" => ref}, socket) do
    {:noreply, socket |> cancel_upload(:avatar, ref) |> assign_avatar_url()}
  end

  def handle_avatar_progress(:avatar, entry, socket) do
    if entry.done?, do: {:noreply, assign_avatar_url(socket)}, else: {:noreply, socket}
  end

  defp save_profile(socket, user_params) do
    case Accounts.update_user_profile(socket.assigns.current_user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile saved.")
         |> assign(:current_user, user)
         |> assign(:profile_form, to_form(Accounts.change_user_profile(user)))
         |> assign_avatar_url()}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset))}
    end
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
    case consume_avatar_upload(socket) do
      {:ok, url} -> {:ok, Map.put(params, "avatar_key", url)}
      :no_upload -> {:ok, params}
      {:error, :missing_public_url} = error -> error
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

  defp settings_tab("profile"), do: :profile
  defp settings_tab("security"), do: :security
  defp settings_tab("account"), do: :security
  defp settings_tab("learning"), do: :profile
  defp settings_tab(_), do: :profile

  # oversize entries are rejected by LiveView itself, wrapped as %{reason: reason}
  defp avatar_upload_error_to_string(%{reason: reason}), do: avatar_upload_error_to_string(reason)
  defp avatar_upload_error_to_string(:too_large), do: "That image is larger than the 2 MB limit."

  defp avatar_upload_error_to_string(:not_accepted),
    do: "Please choose a PNG, JPG, or WEBP image."

  defp avatar_upload_error_to_string(:too_many_files), do: "You can only upload one avatar."

  defp avatar_upload_error_to_string(:image_too_large),
    do: "That image is larger than the 2 MB limit."

  defp avatar_upload_error_to_string(:r2_not_configured),
    do:
      "Image storage isn't configured (missing R2_BUCKET/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/R2_ENDPOINT). " <>
        "Ask an engineer to set these, then try again."

  defp avatar_upload_error_to_string(:unsupported_content_type),
    do: "Please choose a PNG, JPG, or WEBP image."

  defp avatar_upload_error_to_string(message) when is_binary(message), do: message
  defp avatar_upload_error_to_string(_), do: "Could not accept that image."
end
