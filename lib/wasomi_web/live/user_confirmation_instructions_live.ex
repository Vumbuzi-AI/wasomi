defmodule WasomiWeb.UserConfirmationInstructionsLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts

  def render(assigns) do
    ~H"""
    <.auth_shell
      active={:register}
      back_to={~p"/users/register?#{[name: @name || "", email: @confirmed_email || ""]}"}
      back_label="Back to sign up"
    >
      <%= if @display_email do %>
        <h1 class="mt-8 text-4xl font-semibold text-dark">Check your email</h1>
        <p class="mt-2 text-body">
          We sent a confirmation link to your inbox. Open that link to finish activating your account.
        </p>

        <div class="mt-8 rounded-3xl border border-black/5 bg-slate-50 p-5 text-center">
          <p class="text-sm font-medium text-body">Confirmation sent to</p>
          <p class="mt-1 break-words text-lg font-semibold text-dark">
            {@display_email}
          </p>
        </div>

        <.form
          for={@form}
          id="resend_confirmation_form"
          phx-submit="send_instructions"
          class="mt-8 space-y-5"
        >
          <input type="hidden" name="user[email]" value={@display_email} />
          <button
            type="submit"
            phx-disable-with="Sending..."
            class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"
          >
            Resend confirmation link
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

        <%= case @resend_status do %>
          <% :sent -> %>
            <p class="mt-3 text-center text-sm font-medium text-primary">
              ✓ A new confirmation link has been sent to your email.
            </p>
          <% :rate_limited -> %>
            <p class="mt-3 text-center text-sm font-medium text-amber-700">
              You already requested a link recently — check your inbox, or try again in a few minutes.
            </p>
          <% :idle -> %>
        <% end %>
      <% else %>
        <h1 class="mt-8 text-4xl font-semibold text-dark">Resend confirmation</h1>
        <p class="mt-2 text-body">
          Enter your email address to receive a new confirmation link.
        </p>

        <.form
          for={@form}
          id="resend_confirmation_form"
          phx-submit="send_instructions"
          class="mt-8 space-y-5"
        >
          <.auth_input
            field={@form[:email]}
            type="email"
            label="Email address"
            placeholder="you@example.com"
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
            Resend confirmation link
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

        <%= if @resend_status == :sent do %>
          <p class="mt-3 text-center text-sm font-medium text-primary">
            ✓ If your email is in our system, instructions have been sent.
          </p>
        <% end %>
      <% end %>
    </.auth_shell>
    """
  end

  def mount(params, _session, socket) do
    email = params["email"] || ""
    name = params["name"] || ""
    confirmed_email = if email != "", do: email, else: nil

    socket =
      socket
      |> clear_flash()
      |> assign(
        form: to_form(%{"email" => email}, as: "user"),
        page_title: "Confirm email",
        confirmed_email: confirmed_email,
        display_email: display_email(socket.assigns[:current_user], confirmed_email),
        name: if(name != "", do: name, else: nil),
        resend_status: :idle
      )

    {:ok, socket}
  end

  # current_user's real email always wins over a stale/tampered `?email=`
  defp display_email(%{email: email}, _confirmed_email), do: email
  defp display_email(nil, confirmed_email), do: confirmed_email

  def handle_event("send_instructions", _params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    status =
      case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}")) do
        {:ok, _email} -> :sent
        {:error, :rate_limited} -> :rate_limited
        # shouldn't reach here (auth gate redirects confirmed users), but treat as success not error
        {:error, :already_confirmed} -> :sent
      end

    {:noreply, assign(socket, resend_status: status)}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    {:noreply, assign(socket, resend_status: :sent)}
  end
end
