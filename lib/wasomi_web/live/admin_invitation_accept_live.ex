defmodule WasomiWeb.AdminInvitationAcceptLive do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Accounts.User

  def mount(%{"token" => token}, _session, socket) do
    invitation = Accounts.get_pending_admin_invitation_by_token(token)

    account_exists? = invitation && Accounts.get_user_by_email(invitation.email) != nil

    {:ok,
     socket
     |> assign(:page_title, "Accept admin invitation")
     |> assign(:token, token)
     |> assign(:invitation, invitation)
     |> assign(:account_exists?, account_exists?)
     |> assign_new_account_form()}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}
  end

  def handle_event("accept", _params, socket) do
    # Defence in depth: the button only renders for a matching session, but
    # the event must not promote the invited account on a leaked link alone.
    if socket.assigns.invitation && accepting_self?(socket.assigns) do
      case Accounts.accept_admin_invitation(socket.assigns.token) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> put_flash(:info, "You're now a Wasomi admin.")
           |> push_navigate(to: ~p"/admin")}

        {:error, _} ->
          {:noreply, invalidate(socket)}
      end
    else
      {:noreply, invalidate(socket)}
    end
  end

  def handle_event("create", %{"user" => params}, socket) do
    case Accounts.accept_admin_invitation(socket.assigns.token, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Admin account created. Sign in to continue.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "user"))}

      {:error, _} ->
        {:noreply, invalidate(socket)}
    end
  end

  defp invalidate(socket) do
    socket
    |> put_flash(:error, "This invitation link is no longer valid.")
    |> assign(invitation: nil, account_exists?: false)
  end

  defp assign_new_account_form(socket) do
    assign(socket, :form, to_form(Accounts.change_user_registration(%User{}), as: "user"))
  end

  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-slate-50 px-6 py-12">
      <div class="w-full max-w-md rounded-3xl border border-black/5 bg-white p-8 shadow-card">
        <img src={~p"/images/logo.png"} alt="Wasomi" class="h-9 w-auto" />

        <div :if={is_nil(@invitation)} class="mt-8">
          <h1 class="text-2xl font-semibold text-ink">Invitation not found</h1>
          <p class="mt-2 text-body">
            This admin invitation link is invalid, has expired, or has already been used.
          </p>
          <.link navigate={~p"/"} class="mt-6 inline-flex font-medium text-primary hover:text-ink">
            Back to home
          </.link>
        </div>

        <div :if={@invitation} class="mt-8">
          <h1 class="text-2xl font-semibold text-ink">Join the Wasomi admin team</h1>
          <p class="mt-2 text-body">
            You've been invited to be an admin, using <span class="font-medium text-ink">{@invitation.email}</span>.
          </p>

          <%!-- Existing account, signed in as the invited email --%>
          <button
            :if={@account_exists? and accepting_self?(assigns)}
            type="button"
            phx-click="accept"
            phx-disable-with="Accepting..."
            class="mt-6 w-full rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
          >
            Accept and open the admin area
          </button>

          <%!-- Existing account, not signed in as that email --%>
          <div :if={@account_exists? and not accepting_self?(assigns)} class="mt-6">
            <p class="text-sm text-body">
              Sign in with <span class="font-medium text-ink">{@invitation.email}</span>
              to accept this invitation.
            </p>
            <.link
              navigate={~p"/users/log_in"}
              class="mt-4 inline-flex rounded-full bg-ink px-6 py-3 font-medium text-white transition hover:bg-primary"
            >
              Sign in
            </.link>
          </div>

          <%!-- No account yet — create one --%>
          <.form
            :if={not @account_exists?}
            for={@form}
            id="accept_admin_form"
            phx-change="validate"
            phx-submit="create"
            class="mt-6 space-y-4"
          >
            <.input field={@form[:name]} type="text" label="Your name" required />
            <.input field={@form[:password]} type="password" label="Password" required />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              required
            />
            <.button phx-disable-with="Creating..." class="w-full rounded-full bg-ink">
              Create admin account
            </.button>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp accepting_self?(%{current_user: %User{email: email}, invitation: %{email: email}}),
    do: true

  defp accepting_self?(_assigns), do: false
end
