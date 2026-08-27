defmodule WasomiWeb.UserConfirmationInstructionsLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Security.Captcha

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        No confirmation instructions received?
        <:subtitle>We'll send a new confirmation link to your inbox</:subtitle>
      </.header>

      <p
        :if={@captcha_error}
        class="mt-4 rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-600"
      >
        {@captcha_error}
      </p>

      <.simple_form
        for={@form}
        id="resend_confirmation_form"
        phx-submit="send_instructions"
        phx-hook={if @recaptcha_site_key, do: "Recaptcha"}
        data-site-key={@recaptcha_site_key}
        data-action="resend_confirmation"
      >
        <.input field={@form[:email]} type="email" placeholder="Email" required />
        <:actions>
          <.button phx-disable-with="Sending..." class="w-full">
            Resend confirmation instructions
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link href={~p"/users/register"}>Register</.link>
        | <.link href={~p"/users/log_in"}>Log in</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       form: to_form(%{}, as: "user"),
       page_title: "Resend confirmation",
       captcha_error: nil,
       recaptcha_site_key: Captcha.site_key()
     )}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}} = params, socket) do
    captcha_token = params["captcha_token"]

    case Captcha.verify(captcha_token, action: "resend_confirmation") do
      {:ok, _} ->
        socket = clear_flash(socket, :error)

        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )
        end

        info =
          "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> redirect(to: ~p"/")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(captcha_error: "Security verification failed. Please try again.")
         |> put_flash(:error, "Security verification failed. Please try again.")}
    end
  end
end
