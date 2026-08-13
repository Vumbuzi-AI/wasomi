defmodule WasomiWeb.UserLoginLive do
  use WasomiWeb, :live_view

  def render(assigns) do
    ~H"""
    <.auth_shell active={:login}>
      <h1 class="mt-8 text-4xl font-semibold text-dark">Welcome back</h1>
      <p class="mt-2 text-body">Log in to continue learning or manage Wasomi.</p>

      <.form
        for={@form}
        id="login_form"
        action={~p"/users/log_in"}
        phx-update="ignore"
        class="mt-8 space-y-5"
      >
        <.auth_input
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="Enter your email"
          required
        >
          <:icon>
            <svg
              class="h-4 w-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle cx="12" cy="7" r="4" />
            </svg>
          </:icon>
        </.auth_input>

        <div>
          <div class="flex items-center justify-between">
            <label for={@form[:password].id} class="mb-2 block text-sm font-semibold text-dark">
              Password
            </label>
            <.link
              href={~p"/users/reset_password"}
              class="mb-2 text-sm font-medium text-primary hover:underline"
            >
              Forgot your password?
            </.link>
          </div>
          <.auth_input
            field={@form[:password]}
            type="password"
            placeholder="Enter your password"
            required
          >
            <:icon>
              <svg
                class="h-4 w-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <rect x="3" y="11" width="18" height="10" rx="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </:icon>
          </.auth_input>
        </div>

        <label class="flex items-center gap-2.5 text-sm font-medium text-dark">
          <input
            type="checkbox"
            name={@form[:remember_me].name}
            id={@form[:remember_me].id}
            value="true"
            checked
            class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary/30"
          /> Remember me
        </label>

        <button
          type="submit"
          phx-disable-with="Logging in..."
          class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"
        >
          Log in
          <svg
            class="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <line x1="5" y1="12" x2="19" y2="12" /><polyline points="12 5 19 12 12 19" />
          </svg>
        </button>
      </.form>

      <p class="mt-6 text-center text-sm text-body">
        New to Wasomi?
        <.link
          navigate={~p"/users/register"}
          class="font-semibold text-dark underline hover:text-primary"
        >
          Create an account
        </.link>
      </p>
    </.auth_shell>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form, page_title: "Log in"), temporary_assigns: [form: form]}
  end
end
