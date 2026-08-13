defmodule WasomiWeb.UserForgotPasswordLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts

  def render(assigns) do
    ~H"""
    <.auth_shell active={:login}>
      <h1 class="mt-8 text-4xl font-semibold text-dark">Forgot your password?</h1>
      <p class="mt-2 text-body">We'll send a password reset link to your inbox.</p>

      <.form for={@form} id="reset_password_form" phx-submit="send_email" class="mt-8 space-y-5">
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
              <rect x="2" y="4" width="20" height="16" rx="2" /><polyline points="2 6 12 13 22 6" />
            </svg>
          </:icon>
        </.auth_input>

        <button
          type="submit"
          phx-disable-with="Sending..."
          class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"
        >
          Send password reset instructions
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
        <.link
          navigate={~p"/users/register"}
          class="font-semibold text-dark underline hover:text-primary"
        >
          Create an account
        </.link>
        <span class="mx-1 text-black/20">|</span>
        <.link
          navigate={~p"/users/log_in"}
          class="font-semibold text-dark underline hover:text-primary"
        >
          Log in
        </.link>
      </p>
    </.auth_shell>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Forgot password")}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
