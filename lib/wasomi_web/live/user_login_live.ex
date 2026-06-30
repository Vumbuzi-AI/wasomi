defmodule WasomiWeb.UserLoginLive do
  use WasomiWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="flex min-h-[calc(100vh-4rem)] items-center justify-center bg-gradient-to-b from-mint via-white to-white px-5 py-16">
      <div class="grid w-full max-w-5xl overflow-hidden rounded-3xl border border-black/5 bg-white shadow-xl lg:grid-cols-2">
        <div class="relative hidden lg:block">
          <img
            src={~p"/images/login.jpg"}
            alt="Students learning on Wasomi"
            class="h-full w-full object-cover"
          />
          <div class="absolute inset-0 bg-gradient-to-t from-dark/80 via-dark/20 to-transparent">
          </div>
          <div class="absolute inset-x-0 bottom-0 p-10">
            <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
              Welcome back
            </span>
            <h2 class="mt-4 text-3xl font-semibold leading-[1.15] text-white">
              Pick up right where you left off.
            </h2>
            <p class="mt-3 text-white/80">
              Log in to continue your courses, track progress, and access your certificates.
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
            <h1 class="mt-6 text-3xl font-semibold text-dark">Log in to account</h1>
            <p class="mt-2 text-body">
              Don't have an account?
              <.link navigate={~p"/users/register"} class="font-medium text-primary hover:underline">
                Sign up
              </.link>
              for an account now.
            </p>
          </div>

          <.form
            for={@form}
            id="login_form"
            action={~p"/users/log_in"}
            phx-update="ignore"
            class="mt-8 space-y-5"
          >
            <.auth_input field={@form[:email]} type="email" label="Email" required />
            <.auth_input field={@form[:password]} type="password" label="Password" required />

            <div class="flex items-center justify-between">
              <label class="flex items-center gap-2.5 text-sm text-body">
                <input
                  type="checkbox"
                  name={@form[:remember_me].name}
                  id={@form[:remember_me].id}
                  value="true"
                  class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary/30"
                /> Keep me logged in
              </label>
              <.link
                href={~p"/users/reset_password"}
                class="text-sm font-medium text-primary hover:underline"
              >
                Forgot your password?
              </.link>
            </div>

            <button
              type="submit"
              phx-disable-with="Logging in..."
              class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-dark px-6 py-3.5 font-medium text-white transition hover:bg-primary phx-submit-loading:opacity-75"
            >
              Log in
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
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
