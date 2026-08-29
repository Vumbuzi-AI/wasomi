defmodule WasomiWeb.WelcomeLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Accounts.User

  @goal_options [
    {"Career advancement", :career_advancement},
    {"Career switch", :career_switch},
    {"Certification", :certification},
    {"Upskilling", :upskilling},
    {"Personal interest", :personal_interest}
  ]

  @experience_options [
    {"Student", :student},
    {"Entry-level", :entry},
    {"Mid-level", :mid},
    {"Senior", :senior},
    {"Lead / Executive", :lead_executive}
  ]

  # Skip is withheld until the learner engages or this elapses.
  @skip_delay_ms 12_000

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if Accounts.onboarding_completed?(user) do
      {:ok, push_navigate(socket, to: WasomiWeb.UserAuth.signed_in_path(user))}
    else
      if connected?(socket), do: Process.send_after(self(), :reveal_skip, @skip_delay_ms)

      {:ok,
       socket
       |> assign(:page_title, "Welcome to Wasomi")
       |> assign(:goal_options, @goal_options)
       |> assign(:experience_options, @experience_options)
       |> assign(:skip_available, false)
       |> assign_form(Accounts.change_user_profile(user))}
    end
  end

  def handle_info(:reveal_skip, socket), do: {:noreply, assign(socket, :skip_available, true)}

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset) |> assign(:skip_available, true)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_user, params) do
      {:ok, _user} -> {:noreply, finish_onboarding(socket)}
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("skip", _params, socket) do
    {:noreply, finish_onboarding(socket)}
  end

  defp finish_onboarding(socket) do
    {:ok, _user} = Accounts.complete_user_onboarding(socket.assigns.current_user)
    push_navigate(socket, to: ~p"/dashboard")
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "user"))

  def render(assigns) do
    ~H"""
    <.auth_shell active={:onboarding}>
      <h1 class="text-3xl font-semibold text-dark">
        Welcome to Wasomi, {first_name(@current_user)}.
      </h1>
      <p class="mt-2 text-body">
        A few quick details so we can point you at the right courses. You can change these
        any time from your account settings.
      </p>

      <.form
        for={@form}
        id="welcome_form"
        phx-change="validate"
        phx-submit="save"
        class="mt-8 space-y-6"
      >
        <.input
          field={@form[:learning_goal]}
          type="select"
          label="What brings you to Wasomi?"
          prompt="Select a goal"
          options={@goal_options}
        />

        <.input
          field={@form[:experience_level]}
          type="select"
          label="Your experience level"
          prompt="Select your experience level"
          options={@experience_options}
        />

        <.country_combobox field={@form[:country]} />

        <div class="pt-2">
          <div class="flex justify-end">
            <.button phx-disable-with="Saving..." class="rounded-full bg-dark px-6">
              Save &amp; continue
            </.button>
          </div>

          <div class="mt-4 text-center">
            <button
              type="button"
              phx-click="skip"
              data-skip-available={to_string(@skip_available)}
              class={[
                "text-xs text-zinc-400 underline underline-offset-2 transition-opacity duration-1000 ease-out hover:text-zinc-500",
                @skip_available && "opacity-100",
                !@skip_available && "pointer-events-none opacity-0"
              ]}
            >
              Skip for now
            </button>
          </div>
        </div>
      </.form>
    </.auth_shell>
    """
  end

  defp first_name(%User{first_name: first}) when is_binary(first) and first != "", do: first
  defp first_name(_user), do: "there"
end
