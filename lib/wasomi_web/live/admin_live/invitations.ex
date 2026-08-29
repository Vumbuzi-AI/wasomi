defmodule WasomiWeb.AdminLive.Invitations do
  use WasomiWeb, :live_view

  alias Wasomi.Accounts
  alias Wasomi.Accounts.AdminInvitation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin invitations")
     |> assign_form()
     |> load_invitations()}
  end

  @impl true
  def handle_event("validate", %{"invitation" => params}, socket) do
    changeset = params |> AdminInvitation.invite_form_changeset() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: "invitation"))}
  end

  def handle_event("invite", %{"invitation" => %{"email" => email}}, socket) do
    admin = socket.assigns.current_user

    case Accounts.invite_admin(email, admin) do
      {:ok, {invitation, token}} ->
        send_invite(invitation, admin, token)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}.")
         |> assign_form()
         |> load_invitations()}

      {:error, :already_admin} ->
        {:noreply, put_flash(socket, :error, "That email already belongs to an admin.")}

      {:error, :already_invited} ->
        {:noreply,
         put_flash(socket, :error, "There is already a pending invitation for that email.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: "invitation"))}
    end
  end

  def handle_event("resend", %{"id" => id}, socket) do
    admin = socket.assigns.current_user

    case id |> Accounts.get_admin_invitation!() |> Accounts.resend_admin_invitation() do
      {:ok, {invitation, token}} ->
        send_invite(invitation, admin, token)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation re-sent to #{invitation.email}.")
         |> load_invitations()}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "That invitation can no longer be re-sent.")}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    case id |> Accounts.get_admin_invitation!() |> Accounts.revoke_admin_invitation() do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Invitation revoked.") |> load_invitations()}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "That invitation can no longer be revoked.")}
    end
  end

  defp send_invite(invitation, admin, token) do
    Accounts.deliver_admin_invitation(
      invitation.email,
      admin.name,
      url(~p"/admin-invitations/accept/#{token}")
    )
  end

  defp assign_form(socket),
    do: assign(socket, :form, to_form(AdminInvitation.invite_form_changeset(), as: "invitation"))

  defp load_invitations(socket),
    do: assign(socket, :invitations, Accounts.list_admin_invitations())

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:invitations} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.page_header title="Admin invitations">
          <:subtitle>
            Invite people to administer Wasomi. Any admin can invite; links expire after 7 days.
          </:subtitle>
        </.page_header>

        <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <h2 class="text-xl font-semibold text-ink">Invite an admin</h2>
          <.form
            for={@form}
            id="invite_admin_form"
            phx-change="validate"
            phx-submit="invite"
            class="mt-4 flex flex-wrap items-start gap-3"
          >
            <div class="min-w-64 flex-1">
              <.input field={@form[:email]} type="email" placeholder="name@example.com" />
            </div>
            <.button phx-disable-with="Sending..." class="rounded-full bg-ink px-5">
              Send invitation
            </.button>
          </.form>
        </div>

        <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <h2 class="text-xl font-semibold text-ink">Invitations</h2>
            <span class="rounded-full border border-primary/30 bg-mint px-3 py-1 text-xs font-semibold text-primary">
              {length(@invitations)} {ngettext("record", "records", length(@invitations))}
            </span>
          </div>

          <div :if={@invitations != []} class="mt-6 overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead class="text-xs uppercase tracking-wide text-muted">
                <tr>
                  <th class="pb-3 pr-4 font-semibold">Email</th>
                  <th class="pb-3 pr-4 font-semibold">Status</th>
                  <th class="pb-3 pr-4 font-semibold">Invited by</th>
                  <th class="pb-3 pr-4 font-semibold">Expires</th>
                  <th class="pb-3 font-semibold"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-black/5">
                <tr :for={invitation <- @invitations} id={"invitation-#{invitation.id}"}>
                  <td class="py-3 pr-4 font-medium text-ink">{invitation.email}</td>
                  <td class="py-3 pr-4">
                    <span class={[
                      "rounded-full px-2.5 py-0.5 text-xs font-semibold",
                      state_class(Accounts.admin_invitation_state(invitation))
                    ]}>
                      {invitation |> Accounts.admin_invitation_state() |> to_string()}
                    </span>
                  </td>
                  <td class="py-3 pr-4 text-body">
                    {(invitation.invited_by && invitation.invited_by.name) || "—"}
                  </td>
                  <td class="py-3 pr-4 text-body">{format_date(invitation.expires_at)}</td>
                  <td class="py-3 text-right">
                    <div
                      :if={Accounts.admin_invitation_state(invitation) in [:pending, :expired]}
                      class="flex justify-end gap-3"
                    >
                      <button
                        type="button"
                        phx-click="resend"
                        phx-value-id={invitation.id}
                        class="text-sm font-medium text-primary transition hover:text-ink"
                      >
                        Resend
                      </button>
                      <button
                        type="button"
                        phx-click="revoke"
                        phx-value-id={invitation.id}
                        data-confirm="Revoke this invitation?"
                        class="text-sm font-medium text-rose-600 transition hover:text-rose-700"
                      >
                        Revoke
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@invitations == []} class="mt-6 rounded-2xl bg-surface p-5 text-body">
            No invitations yet.
          </p>
        </div>
      </div>
    </.admin_layout>
    """
  end

  defp state_class(:pending), do: "bg-mint text-primary"
  defp state_class(:accepted), do: "bg-emerald-50 text-emerald-700"
  defp state_class(:revoked), do: "bg-zinc-100 text-zinc-500"
  defp state_class(:expired), do: "bg-amber-50 text-amber-700"

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
