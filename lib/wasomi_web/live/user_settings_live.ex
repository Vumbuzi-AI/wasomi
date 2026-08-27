defmodule WasomiWeb.UserSettingsLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts

  def render(assigns) do
    ~H"""
    <.student_layout active={:account} current_user={@current_user}>
      <div class="mx-auto max-w-3xl px-5 py-10 lg:px-10 lg:py-12">
        <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8">
          <.header>
            Account Settings
            <:subtitle>Manage your account email address and password settings</:subtitle>
          </.header>
        </div>

        <div class="mt-6 space-y-6">
          <section
            id="email-settings-card"
            class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8"
          >
            <div>
              <h2 class="text-xl font-semibold text-ink">Email</h2>
              <p class="mt-1 text-sm text-body">
                Update the address you use to sign in and receive account messages.
              </p>
            </div>

            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
              class="mt-7 space-y-6"
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
              <div class="flex items-center justify-end">
                <.button phx-disable-with="Changing..." class="rounded-full bg-ink px-5">
                  Change Email
                </.button>
              </div>
            </.form>
          </section>

          <section
            id="password-settings-card"
            class="rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8"
          >
            <div>
              <h2 class="text-xl font-semibold text-ink">Password</h2>
              <p class="mt-1 text-sm text-body">
                Choose a strong password and confirm the change with your current password.
              </p>
            </div>

            <.form
              for={@password_form}
              id="password_form"
              action={~p"/users/log_in?_action=password_updated"}
              method="post"
              phx-change="validate_password"
              phx-submit="update_password"
              phx-trigger-action={@trigger_submit}
              class="mt-7 space-y-6"
            >
              <input
                name={@password_form[:email].name}
                type="hidden"
                id="hidden_user_email"
                value={@current_email}
              />
              <.input field={@password_form[:password]} type="password" label="New password" required />
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
              <div class="flex items-center justify-end">
                <.button phx-disable-with="Changing..." class="rounded-full bg-ink px-5">
                  Change Password
                </.button>
              </div>
            </.form>
          </section>
        </div>
      </div>
    </.student_layout>
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

    socket =
      socket
      |> assign(:page_title, "Account settings")
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
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
end
