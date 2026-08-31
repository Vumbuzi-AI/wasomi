defmodule WasomiWeb.NotificationsLive do
  use WasomiWeb, :live_view

  alias Wasomi.Notifications

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Notifications.subscribe(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Notifications")
     |> refresh_notifications()}
  end

  @impl true
  def handle_info({:notification_created, _notification}, socket) do
    {:noreply, refresh_notifications(socket)}
  end

  def handle_info({event, _subject}, socket)
      when event in [:enrollment_granted, :payment_confirmed, :certificate_ready] do
    {:noreply, refresh_notifications(socket)}
  end

  @impl true
  def handle_event("dismiss_notification", %{"id" => id}, socket) do
    case Notifications.get_notification(socket.assigns.current_user, id) do
      nil ->
        {:noreply, socket}

      notification ->
        Notifications.mark_read(notification)
        {:noreply, refresh_notifications(socket)}
    end
  end

  # A plain `navigate` link would never fire an event at all, leaving an
  # acted-on notification stuck "unread" forever — visiting the course is
  # every bit as much "handled" as clicking Dismiss.
  def handle_event("visit_course", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Notifications.get_notification(user, id) do
      %{course: %{slug: slug}} = notification ->
        Notifications.mark_read(notification)

        {:noreply,
         push_navigate(socket, to: course_destination(notification, slug, user.role == :admin))}

      _ ->
        {:noreply, socket}
    end
  end

  # Admins aren't enrolled, so the learner course player would bounce them to
  # checkout — send them to the admin discussions hub instead.
  defp course_destination(%{kind: kind} = notification, slug, true)
       when kind in [:channel_announcement, :channel_mention] do
    params =
      case notification.channel_message_id do
        nil -> %{course: slug}
        msg_id -> %{course: slug, msg: msg_id}
      end

    ~p"/admin/discussions?#{params}"
  end

  defp course_destination(%{kind: kind} = notification, slug, false)
       when kind in [:channel_announcement, :channel_mention] do
    params =
      case notification.channel_message_id do
        nil -> %{tab: "discussion"}
        msg_id -> %{tab: "discussion", msg: msg_id}
      end

    ~p"/learn/courses/#{slug}?#{params}"
  end

  defp course_destination(_notification, slug, true), do: ~p"/admin/courses/#{slug}"
  defp course_destination(_notification, slug, false), do: ~p"/learn/courses/#{slug}"

  defp cta_label(%{kind: kind}) when kind in [:channel_announcement, :channel_mention],
    do: "Open discussion"

  defp cta_label(_notification), do: "Go to course"

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:notifications} current_user={@current_user}>
      <div class="px-5 py-8 lg:px-8 lg:py-10">
        <section class="rounded-[1.75rem] border border-black/5 bg-white px-6 py-8 shadow-sm sm:px-8">
          <div class="flex flex-wrap items-center justify-between gap-5">
            <div>
              <h1 class="text-4xl font-semibold leading-tight text-ink sm:text-5xl">
                Notifications
              </h1>
              <p class="mt-3 max-w-2xl text-lg text-body">
                Keep track of course access, learning nudges and account updates.
              </p>
            </div>
            <span class="grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-bell" class="h-7 w-7" />
            </span>
          </div>
        </section>

        <section class="mt-6 rounded-[1.75rem] border border-black/5 bg-white p-6 shadow-sm sm:p-8">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p class="text-sm font-semibold uppercase tracking-wider text-primary">
                Inbox
              </p>
              <h2 class="mt-2 text-2xl font-semibold text-ink">
                {@unread_count} unread
              </h2>
            </div>
          </div>

          <div
            :if={@notifications != []}
            class="mt-6 divide-y divide-black/5 overflow-hidden rounded-2xl border border-black/5"
          >
            <article
              :for={notification <- @notifications}
              id={"notification-#{notification.id}"}
              class={[
                "flex flex-wrap items-start justify-between gap-4 px-5 py-4 transition sm:px-6",
                unread?(notification) &&
                  "bg-mint/20",
                !unread?(notification) &&
                  "bg-white"
              ]}
            >
              <div class="min-w-0 flex-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class={[
                    "rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase",
                    unread?(notification) && "bg-white text-primary",
                    !unread?(notification) && "bg-surface text-muted"
                  ]}>
                    {status_label(notification)}
                  </span>
                  <span class="text-xs text-muted">
                    {format_datetime(notification.inserted_at)}
                  </span>
                </div>
                <h3 class="mt-2 text-base font-semibold text-ink">{notification.title}</h3>
                <p class="mt-1 text-sm leading-5 text-body">{notification.body}</p>
              </div>

              <div class="flex shrink-0 items-center gap-2">
                <button
                  :if={notification.course}
                  type="button"
                  phx-click="visit_course"
                  phx-value-id={notification.id}
                  class="rounded-full bg-primary px-3 py-1.5 text-sm font-semibold text-white transition hover:bg-ink"
                >
                  {cta_label(notification)}
                </button>
                <button
                  :if={unread?(notification)}
                  type="button"
                  phx-click="dismiss_notification"
                  phx-value-id={notification.id}
                  class="rounded-full px-3 py-1.5 text-sm font-semibold text-primary transition hover:bg-white hover:text-ink"
                >
                  Dismiss
                </button>
              </div>
            </article>
          </div>

          <div :if={@notifications == []} id="notifications-empty" class="py-14 text-center">
            <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
              <.icon name="hero-bell-slash" class="h-7 w-7" />
            </span>
            <h3 class="mt-5 text-xl font-semibold text-ink">Nothing to catch up on.</h3>
            <p class="mx-auto mt-2 max-w-lg text-body">
              Course updates and learning reminders will appear here when there is something new.
            </p>
          </div>
        </section>
      </div>
    </.student_layout>
    """
  end

  defp refresh_notifications(socket) do
    user = socket.assigns.current_user
    notifications = Notifications.list_for_user(user)

    socket
    |> assign(:notifications, notifications)
    |> assign(:unread_count, Enum.count(notifications, &unread?/1))
  end

  defp unread?(notification), do: is_nil(notification.read_at)

  defp status_label(notification) do
    if unread?(notification), do: "Unread", else: "Read"
  end

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %-d, %Y at %-I:%M %p")
  end

  defp format_datetime(_datetime), do: "Date unavailable"
end
