defmodule WasomiWeb.UserLoginLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Security.Captcha

  @email_re ~r/^[^\s]+@[^\s]+$/

  def mount(params, _session, socket) do
    # UserSessionController bounces a low reCAPTCHA score back here with the
    # email in the flash — resume on the choose step, not the email step.
    resumed_email = Phoenix.Flash.get(socket.assigns.flash, :email)
    show_recaptcha_v2 = params["show_recaptcha_v2"] == "true"

    {:ok,
     socket
     |> assign(:page_title, "Log in")
     |> assign(:step, if(resumed_email || show_recaptcha_v2, do: :choose, else: :email))
     |> assign(:email, resumed_email || "")
     |> assign(:email_error, nil)
     |> assign(:email_form, to_form(%{"email" => resumed_email}, as: "user"))
     |> assign(
       :captcha_error,
       show_recaptcha_v2 && "For your security, please also complete the checkbox below."
     )
     |> assign(:show_recaptcha_v2, show_recaptcha_v2)
     |> assign(:recaptcha_site_key, Captcha.site_key())
     |> assign(:recaptcha_v2_site_key, Captcha.v2_site_key())}
  end

  def handle_event("continue", %{"user" => %{"email" => email}}, socket) do
    email = String.trim(email)

    if email =~ @email_re do
      {:noreply, assign(socket, step: :choose, email: email, email_error: nil)}
    else
      {:noreply, assign(socket, email_error: "Enter a valid email address.")}
    end
  end

  def handle_event("restart", _params, socket) do
    {:noreply,
     assign(socket,
       step: :email,
       email_error: nil,
       captcha_error: nil,
       show_recaptcha_v2: false,
       email_form: to_form(%{"email" => socket.assigns.email}, as: "user")
     )}
  end

  def handle_event("send_link", params, socket) do
    case Captcha.verify_from_params(params, action: "magic_link") do
      {:ok, _} ->
        Accounts.deliver_magic_link(socket.assigns.email, &url(~p"/users/log_in/#{&1}"))
        {:noreply, assign(socket, step: :sent, captcha_error: nil, show_recaptcha_v2: false)}

      {:error, :low_score} ->
        {:noreply,
         assign(socket,
           show_recaptcha_v2: true,
           captcha_error: "For your security, please also complete the checkbox below."
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket, captcha_error: "Security verification failed. Please try again.")}
    end
  end

  def handle_event("resend", _params, socket) do
    Accounts.deliver_magic_link(socket.assigns.email, &url(~p"/users/log_in/#{&1}"))
    {:noreply, put_flash(socket, :info, "Sent again — check your inbox.")}
  end

  def handle_event("recaptcha_blocked", _params, socket) do
    {:noreply,
     assign(socket,
       captcha_error:
         "We couldn't load our security check. Please disable any ad blocker or " <>
           "privacy extension for this site, then try again."
     )}
  end

  def render(assigns) do
    ~H"""
    <.auth_shell active={:login}>
      <h1 class="mt-8 text-4xl font-semibold text-dark">Welcome back</h1>
      <p class="mt-2 text-body">Log in to continue learning or manage Wasomi.</p>

      <.step_email :if={@step == :email} {assigns} />
      <.step_choose :if={@step == :choose} {assigns} />
      <.step_sent :if={@step == :sent} {assigns} />

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

  defp step_email(assigns) do
    ~H"""
    <.form for={@email_form} id="login_email_form" phx-submit="continue" class="mt-8 space-y-5">
      <.auth_input
        field={@email_form[:email]}
        type="email"
        label="Email"
        placeholder="Enter your email"
        autocomplete="email"
        required
      >
        <:icon><.mail_icon /></:icon>
      </.auth_input>

      <p :if={@email_error} class="text-sm font-medium text-rose-600">{@email_error}</p>

      <button type="submit" class={submit_class()}>
        Continue <.arrow_icon />
      </button>
    </.form>
    """
  end

  defp step_choose(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="flex items-center justify-between rounded-2xl bg-slate-50 px-4 py-3">
        <span class="truncate text-sm font-medium text-dark">{@email}</span>
        <button
          type="button"
          phx-click="restart"
          class="shrink-0 text-sm font-medium text-primary hover:underline"
        >
          Change
        </button>
      </div>

      <.form
        for={%{}}
        id="login_form"
        action={~p"/users/log_in"}
        phx-update="ignore"
        phx-hook={if @recaptcha_site_key || @recaptcha_v2_site_key, do: "Recaptcha"}
        data-site-key={@recaptcha_site_key}
        data-v2-site-key={@recaptcha_v2_site_key}
        data-show-v2={if @show_recaptcha_v2, do: "true", else: "false"}
        data-action="login"
        class="mt-5 space-y-5"
      >
        <input type="hidden" name="user[email]" value={@email} />

        <div>
          <div class="flex items-center justify-between">
            <label for="login_password" class="mb-2 block text-sm font-semibold text-dark">
              Password
            </label>
            <.link
              href={~p"/users/reset_password"}
              class="mb-2 text-sm font-medium text-primary hover:underline"
            >
              Forgot your password?
            </.link>
          </div>
          <div class="flex items-center gap-2 rounded-lg border border-black/15 bg-white px-3.5 py-3 focus-within:border-primary focus-within:ring-4 focus-within:ring-primary/10">
            <span class="shrink-0 text-muted"><.lock_icon /></span>
            <input
              type="password"
              name="user[password]"
              id="login_password"
              autocomplete="current-password"
              autofocus
              required
              placeholder="Enter your password"
              class="w-full border-0 bg-transparent p-0 font-medium text-dark outline-none placeholder:font-medium placeholder:text-muted focus:outline-none focus:ring-0"
            />
          </div>
        </div>

        <label class="flex items-center gap-2.5 text-sm font-medium text-dark">
          <input
            type="checkbox"
            name="user[remember_me]"
            value="true"
            checked
            class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary/30"
          /> Remember me
        </label>

        <p
          :if={@captcha_error}
          class="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-600"
        >
          {@captcha_error}
        </p>

        <.recaptcha_v3_widget :if={@recaptcha_site_key} form_id="login_form" />
        <.recaptcha_v2_widget
          :if={@recaptcha_v2_site_key}
          show?={@show_recaptcha_v2}
          form_id="login_form"
        />

        <button type="submit" phx-disable-with="Logging in..." class={submit_class()}>
          Log in <.arrow_icon />
        </button>
      </.form>

      <div class="mt-6 flex items-center gap-3 text-xs font-medium uppercase tracking-wide text-black/30">
        <span class="h-px flex-1 bg-black/10"></span> or <span class="h-px flex-1 bg-black/10"></span>
      </div>

      <.form
        for={%{}}
        id="magic_link_form"
        phx-submit="send_link"
        phx-hook={if @recaptcha_site_key || @recaptcha_v2_site_key, do: "Recaptcha"}
        data-site-key={@recaptcha_site_key}
        data-v2-site-key={@recaptcha_v2_site_key}
        data-show-v2={if @show_recaptcha_v2, do: "true", else: "false"}
        data-action="magic_link"
        class="mt-6"
      >
        <.recaptcha_v3_widget :if={@recaptcha_site_key} form_id="magic_link_form" />
        <.recaptcha_v2_widget
          :if={@recaptcha_v2_site_key}
          show?={@show_recaptcha_v2}
          form_id="magic_link_form"
        />
        <button
          type="submit"
          phx-disable-with="Sending..."
          class="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-full bg-dark px-6 py-3.5 font-semibold text-white transition hover:bg-primary"
        >
          <.mail_icon /> Email me a login link instead
        </button>
      </.form>
    </div>
    """
  end

  defp step_sent(assigns) do
    ~H"""
    <div class="mt-8">
      <div class="rounded-2xl bg-mint p-5 text-body">
        <p class="font-semibold text-dark">Check your email</p>
        <p class="mt-1 text-sm">
          If <span class="font-medium text-dark">{@email}</span>
          has an account, a one-time login link is on its way. It expires in 15 minutes.
        </p>
      </div>

      <div class="mt-6 flex flex-col gap-3">
        <button type="button" phx-click="resend" class={submit_class()}>
          Resend the link
        </button>
        <button
          type="button"
          phx-click="restart"
          class="text-sm font-medium text-primary hover:underline"
        >
          Use a different email
        </button>
      </div>
    </div>
    """
  end

  defp submit_class,
    do:
      "group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"

  defp mail_icon(assigns) do
    ~H"""
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
    """
  end

  defp lock_icon(assigns) do
    ~H"""
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
    """
  end

  defp arrow_icon(assigns) do
    ~H"""
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
    """
  end
end
