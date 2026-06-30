defmodule WasomiWeb.UserRegistrationLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Accounts.User

  def render(assigns) do
    ~H"""
    <div class="flex min-h-[calc(100vh-4rem)] items-center justify-center bg-gradient-to-b from-mint via-white to-white px-5 py-16">
      <div class="grid w-full max-w-5xl overflow-hidden rounded-3xl border border-black/5 bg-white shadow-xl lg:grid-cols-2">
        <div class="relative hidden lg:block">
          <img
            src={~p"/images/signup.jpg"}
            alt="Students learning on Wasomi"
            class="h-full w-full object-cover"
          />
          <div class="absolute inset-0 bg-gradient-to-t from-dark/80 via-dark/20 to-transparent">
          </div>
          <div class="absolute inset-x-0 bottom-0 p-10">
            <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
              Join Wasomi
            </span>
            <h2 class="mt-4 text-3xl font-semibold leading-[1.15] text-white">
              Start learning the skills that move you forward.
            </h2>
            <p class="mt-3 text-white/80">
              Create an account to enroll in courses, track your progress, and earn certificates.
            </p>
          </div>
        </div>

        <div class="p-8 sm:p-10">
          <div class="text-center">
            <a href="/" class="inline-flex items-center gap-2.5">
              <span class="grid h-10 w-10 place-items-center rounded-[10px] bg-primary">
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none">
                  <path
                    d="M5 18V8l7 7 7-7v10"
                    stroke="#fff"
                    stroke-width="2.3"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </span>
            </a>
            <h1 class="mt-6 text-3xl font-semibold text-dark">Register for an account</h1>
            <p class="mt-2 text-body">
              Already registered?
              <.link navigate={~p"/users/log_in"} class="font-medium text-primary hover:underline">
                Log in
              </.link>
              to your account now.
            </p>
          </div>

          <.form
            for={@form}
            id="registration_form"
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            action={~p"/users/log_in?_action=registered"}
            method="post"
            class="mt-8 space-y-5"
          >
            <p
              :if={@check_errors}
              class="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-600"
            >
              Oops, something went wrong! Please check the errors below.
            </p>

            <.auth_input field={@form[:name]} type="text" label="Name" required />
            <.auth_input field={@form[:email]} type="email" label="Email" required />
            <.auth_input field={@form[:password]} type="password" label="Password" required />

            <button
              type="submit"
              phx-disable-with="Creating account..."
              class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-dark px-6 py-3.5 font-medium text-white transition hover:bg-primary phx-submit-loading:opacity-75"
            >
              Create an account
              <span class="grid h-7 w-7 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none">
                  <path
                    d="M5 12h14m-6-6 6 6-6 6"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </span>
            </button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
