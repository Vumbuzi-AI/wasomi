defmodule WasomiWeb.UserResetPasswordLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts

  def render(assigns) do
    ~H"""
    <.auth_shell active={:login}>
      <h1 class="mt-8 text-4xl font-semibold text-dark">Reset Password</h1>
      <p class="mt-2 text-body">Choose a new password for your account.</p>

      <.form
        for={@form}
        id="reset_password_form"
        phx-submit="reset_password"
        phx-change="validate"
        class="mt-8 space-y-5"
      >
        <p
          :if={@form.errors != []}
          class="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-600"
        >
          Please fix the errors below and try again.
        </p>

        <.auth_input
          field={@form[:password]}
          type="password"
          label="New password"
          placeholder="Enter a new password"
          required
        >
          <:icon><.icon name="hero-lock-closed" class="h-4 w-4" /></:icon>
        </.auth_input>
        <.auth_input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          placeholder="Re-enter the new password"
          required
        >
          <:icon><.icon name="hero-lock-closed" class="h-4 w-4" /></:icon>
        </.auth_input>

        <button
          type="submit"
          phx-disable-with="Resetting..."
          class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"
        >
          Reset Password
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
        <.link href={~p"/users/register"} class="font-semibold text-dark underline hover:text-primary">
          Register
        </.link>
        <span class="mx-1 text-black/20">|</span>
        <.link href={~p"/users/log_in"} class="font-semibold text-dark underline hover:text-primary">
          Log in
        </.link>
      </p>
    </.auth_shell>
    """
  end

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, socket |> assign(:page_title, "Reset password") |> assign_form(form_source),
     temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
