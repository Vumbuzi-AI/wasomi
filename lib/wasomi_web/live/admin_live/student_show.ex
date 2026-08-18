defmodule WasomiWeb.AdminLive.StudentShow do
  use WasomiWeb, :live_view

  alias Wasomi.{Accounts, Catalog, Enrollments, Payments}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = Accounts.get_user!(id)
    payments = Payments.list_payments_for_user(user.id)

    spent_minor =
      payments
      |> Enum.filter(&(&1.status == :successful))
      |> Enum.map(& &1.amount_minor)
      |> Enum.sum()

    {:ok,
     socket
     |> assign(:page_title, user.name || user.email)
     |> assign(:user, user)
     |> assign(:payments, payments)
     |> assign(:spent_minor, spent_minor)
     |> assign(:modal, nil)
     |> assign(:grant_access_form, to_form(Enrollments.change_grant_access()))
     |> refresh_enrollments()}
  end

  @impl true
  def handle_event("open_grant_access", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, :grant_access)
     |> assign(:grant_access_form, to_form(Enrollments.change_grant_access()))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  def handle_event("validate_grant_access", %{"grant_access_form" => params}, socket) do
    form =
      params
      |> Enrollments.change_grant_access()
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :grant_access_form, form)}
  end

  def handle_event("grant_access", %{"grant_access_form" => params}, socket) do
    case Enrollments.grant_access(socket.assigns.user, socket.assigns.current_user, params) do
      {:ok, _enrollment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Access granted. The learner has been notified by email and in-app.")
         |> assign(:modal, nil)
         |> refresh_enrollments()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :grant_access_form, to_form(changeset, action: :validate))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to grant course access.")}
    end
  end

  defp refresh_enrollments(socket) do
    user = socket.assigns.user
    enrollments = Enrollments.list_active_for_user(user)
    enrolled_course_ids = MapSet.new(enrollments, & &1.course_id)

    grantable_courses =
      Catalog.list_courses()
      |> Enum.filter(&(&1.status == :published))
      |> Enum.reject(&MapSet.member?(enrolled_course_ids, &1.id))

    socket
    |> assign(:enrollments, enrollments)
    |> assign(:grantable_courses, grantable_courses)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.admin_layout active={:students} current_user={@current_user}>
      <div class="w-full space-y-5 px-5 py-8 lg:px-8">
        <.link
          navigate={~p"/admin/students"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" /> Back to students
        </.link>

        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex flex-wrap items-center gap-4">
            <span class="grid h-16 w-16 shrink-0 place-items-center rounded-full bg-mint text-2xl font-semibold uppercase text-primary">
              {String.first(@user.name || @user.email)}
            </span>
            <div>
              <h1 class="text-3xl font-semibold text-ink">{@user.name || "Learner"}</h1>
              <p class="text-body">{@user.email}</p>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm text-muted">
                <span :if={@user.phone}>{@user.phone}</span>
                <.status_badge status={@user.role} />
                <span>Joined {format_date(@user.inserted_at)}</span>
              </div>
            </div>
          </div>

          <button
            type="button"
            phx-click="open_grant_access"
            disabled={@grantable_courses == []}
            title={
              if @grantable_courses == [],
                do: "This learner already has active access to every course.",
                else: "Grant course access"
            }
            class="group inline-flex shrink-0 items-center gap-2 rounded-full bg-ink py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-ink"
          >
            Grant access
            <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-ink">
              <.icon name="hero-key" class="h-4 w-4" />
            </span>
          </button>
        </div>

        <div class="grid gap-5 sm:grid-cols-3">
          <.stat_card
            label="Total spent"
            value={Payments.format_minor(@spent_minor)}
            icon="hero-banknotes"
          />
          <.stat_card label="Active courses" value={length(@enrollments)} icon="hero-academic-cap" />
          <.stat_card
            label="Email confirmed"
            value={if @user.confirmed_at, do: "Yes", else: "No"}
            icon="hero-check-badge"
          />
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
          <%!-- Enrolled courses --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6">
            <h2 class="text-xl font-semibold text-ink">Enrolled courses</h2>

            <div :if={@enrollments != []} class="mt-5 divide-y divide-black/5">
              <.link
                :for={enrollment <- @enrollments}
                navigate={~p"/admin/courses/#{enrollment.course.slug}"}
                class="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0 transition hover:opacity-80"
              >
                <div class="min-w-0">
                  <p class="truncate font-medium text-ink">{enrollment.course.title}</p>
                  <p class="text-xs text-muted">Enrolled {format_date(enrollment.activated_at)}</p>
                </div>
                <.icon name="hero-chevron-right-mini" class="h-4 w-4 shrink-0 text-muted" />
              </.link>
            </div>

            <p :if={@enrollments == []} class="mt-5 rounded-2xl bg-neutral-50 p-5 text-body">
              This learner has no active enrollments.
            </p>
          </section>

          <%!-- Payment history --%>
          <section class="rounded-3xl border border-black/5 bg-white p-6">
            <h2 class="text-xl font-semibold text-ink">Payment history</h2>

            <div :if={@payments != []} class="mt-5 divide-y divide-black/5">
              <div :for={payment <- @payments} class="py-3 first:pt-0 last:pb-0">
                <div class="flex items-center justify-between gap-4">
                  <div class="min-w-0">
                    <p class="truncate font-medium text-ink">
                      {payment.course && payment.course.title}
                    </p>
                    <p class="text-xs text-muted">
                      {format_date(payment.inserted_at)} · {payment.provider_reference}
                    </p>
                  </div>
                  <div class="shrink-0 text-right">
                    <p class="font-semibold text-ink">{Payments.format_amount(payment)}</p>
                    <.status_badge status={payment.status} />
                  </div>
                </div>
              </div>
            </div>

            <p :if={@payments == []} class="mt-5 rounded-2xl bg-neutral-50 p-5 text-body">
              No payments recorded for this learner.
            </p>
          </section>
        </div>
      </div>

      <.modal
        :if={@modal == :grant_access}
        id="grant-access-modal"
        show
        on_cancel={JS.push("close_modal")}
      >
        <.header>
          Grant course access
          <:subtitle>
            Immediately activate access for {@user.name || @user.email}. They'll be notified by
            email and in-app.
          </:subtitle>
        </.header>

        <.simple_form
          for={@grant_access_form}
          id="grant-access-form"
          phx-change="validate_grant_access"
          phx-submit="grant_access"
        >
          <div>
            <p class="text-sm font-medium text-ink">Learner</p>
            <p class="mt-1 rounded-xl bg-neutral-50 px-3 py-2.5 text-sm text-body">
              {@user.name || "Learner"} · {@user.email}
            </p>
          </div>

          <.input
            field={@grant_access_form[:course_id]}
            type="select"
            label="Course"
            prompt="Select a course"
            options={Enum.map(@grantable_courses, &{&1.title, &1.id})}
            required
          />

          <.input
            field={@grant_access_form[:reason]}
            type="textarea"
            label="Reason for granting access"
            placeholder="e.g. Manual enrollment for a partner scholarship"
            rows="3"
            required
          />

          <:actions>
            <.button phx-disable-with="Granting access...">Grant access</.button>
          </:actions>
        </.simple_form>
      </.modal>
    </.admin_layout>
    """
  end

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp format_date(_), do: "—"
end
