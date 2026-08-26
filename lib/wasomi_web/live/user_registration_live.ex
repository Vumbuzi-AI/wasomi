defmodule WasomiWeb.UserRegistrationLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Accounts.User

  def render(assigns) do
    ~H"""
    <.auth_shell active={:register}>
      <h1 class="mt-8 text-4xl font-semibold text-dark">Create your account</h1>
      <p class="mt-2 text-body">Join Wasomi and start your first learning path.</p>

      <.form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        class="mt-8 space-y-5"
      >
        <p
          :if={@check_errors}
          class="rounded-2xl bg-rose-50 px-4 py-3 text-sm font-medium text-rose-600"
        >
          Oops, something went wrong! Please check the errors below.
        </p>

        <.auth_input
          field={@form[:name]}
          type="text"
          label="Full name"
          placeholder="Enter your full name"
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

        <div class="space-y-2">
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

          <p :if={@email_taken?} class="text-xs text-body">
            Already have an account?
            <.link navigate={~p"/users/log_in"} class="font-semibold text-dark underline">
              Log in
            </.link>
            or
            <.link
              navigate={~p"/users/confirm?#{[email: @form[:email].value || ""]}"}
              class="font-semibold text-dark underline"
            >
              resend the confirmation email
            </.link>
            .
          </p>

          <div
            :if={@email_suggestion}
            id="email-suggestion-box"
            class="flex items-center justify-between gap-3 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2.5 text-xs text-amber-900"
          >
            <span>
              Did you mean <strong class="font-semibold">{@email_suggestion}</strong>?
            </span>
            <button
              type="button"
              phx-click="apply_suggestion"
              phx-value-suggestion={@email_suggestion}
              class="shrink-0 rounded-full bg-amber-200/90 px-3 py-1 font-semibold text-amber-900 transition hover:bg-amber-300 active:scale-95"
            >
              Apply
            </button>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <.auth_input
            field={@form[:password]}
            type="password"
            label="Password"
            placeholder="Min. 6 characters"
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

          <.auth_input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            placeholder="Repeat"
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

        <label
          id="terms-agreement"
          phx-update="ignore"
          class="flex items-center gap-2.5 text-sm font-medium text-dark"
        >
          <input
            type="checkbox"
            required
            class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary/30"
          /> I agree to the terms and privacy policy
        </label>

        <button
          type="submit"
          phx-disable-with="Creating account..."
          class="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-slate-100 px-6 py-3.5 font-semibold text-dark transition hover:bg-dark hover:text-white phx-submit-loading:opacity-75"
        >
          Create account
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
        Already have an account?
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

  def mount(params, _session, socket) do
    current_params =
      %{}
      |> maybe_put_param("name", params["name"])
      |> maybe_put_param("email", params["email"])

    changeset = Accounts.change_user_registration(%User{}, current_params)

    socket =
      socket
      |> assign(
        page_title: "Register",
        check_errors: false,
        email_suggestion: nil,
        current_params: current_params
      )
      |> assign_form(changeset)

    {:ok, socket}
  end

  defp maybe_put_param(map, _key, nil), do: map
  defp maybe_put_param(map, _key, ""), do: map
  defp maybe_put_param(map, key, value), do: Map.put(map, key, value)

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        {:noreply,
         push_navigate(socket, to: ~p"/users/confirm?#{[email: user.email, name: user.name]}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    email = user_params["email"]

    suggestion =
      case Accounts.suggest_email_typo(email) do
        {:ok, suggested} -> suggested
        :none -> nil
      end

    socket =
      socket
      |> assign(email_suggestion: suggestion, current_params: user_params)
      |> assign_form(Map.put(changeset, :action, :validate))

    {:noreply, socket}
  end

  def handle_event("apply_suggestion", %{"suggestion" => suggestion}, socket) do
    current_params =
      socket.assigns.current_params
      |> Map.put("email", suggestion)

    changeset = Accounts.change_user_registration(%User{}, current_params)

    socket =
      socket
      |> assign(email_suggestion: nil, current_params: current_params)
      |> assign_form(Map.put(changeset, :action, :validate))

    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    socket = assign(socket, form: form, email_taken?: email_taken?(changeset))

    if changeset.valid? do
      assign(socket, check_errors: false)
    else
      socket
    end
  end

  defp email_taken?(changeset) do
    Enum.any?(changeset.errors, fn
      {:email, {"has already been taken", _}} -> true
      _ -> false
    end)
  end
end
