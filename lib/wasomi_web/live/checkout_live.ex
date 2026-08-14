defmodule WasomiWeb.CheckoutLive do
  use WasomiWeb, :live_view

  require Logger

  alias Wasomi.{Accounts.User, Catalog, Enrollments, Payments}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    course = Catalog.get_published_course_by_slug!(slug)
    user = socket.assigns.current_user

    cond do
      Enrollments.can_access_course?(user, course) ->
        {:ok, redirect(socket, to: ~p"/learn/courses/#{course.slug}")}

      course.is_free ->
        case Enrollments.enroll_free_course(user, course) do
          {:ok, _enrollment} ->
            {:ok,
             socket
             |> put_flash(:info, "Enrolled in #{course.title} successfully.")
             |> redirect(to: ~p"/learn/courses/#{course.slug}")}

          {:error, :unauthenticated} ->
            {:ok,
             socket
             |> put_flash(:error, "Please log in to enroll in this free course.")
             |> redirect(to: ~p"/users/log_in")}

          {:error, _reason} ->
            {:ok,
             socket
             |> put_flash(:error, "Could not enroll in course. Please try again.")
             |> redirect(to: ~p"/courses/#{course.slug}")}
        end

      true ->
        if connected?(socket), do: Payments.subscribe(user)

        {:ok,
         socket
         |> assign(:page_title, "Checkout · #{course.title}")
         |> assign(:course, course)
         |> assign(:submitting, false)
         |> assign(:waiting, false)
         |> assign(:phone, "")
         |> assign(:phone_error, nil)}
    end
  end

  @impl true
  def handle_event("pay", %{"phone" => phone}, socket) do
    normalized = User.normalize_phone(String.trim(phone))

    if normalized =~ ~r/^2547\d{8}$/ do
      socket = assign(socket, submitting: true, phone: normalized, phone_error: nil)

      case Payments.initialize_checkout(
             socket.assigns.current_user,
             socket.assigns.course,
             normalized
           ) do
        {:ok, %{authorization_url: url}} ->
          {:noreply, redirect(socket, external: url)}

        {:ok, %{enrollment: _enrollment}} ->
          {:noreply,
           socket
           |> put_flash(:info, "Enrolled successfully.")
           |> redirect(to: ~p"/learn/courses/#{socket.assigns.course.slug}")}

        {:error, reason} ->
          Logger.error(
            "Paystack checkout could not be started: #{describe_checkout_error(reason)}"
          )

          {:noreply,
           socket
           |> assign(:submitting, false)
           |> put_flash(:error, "Paystack checkout could not be started. Please try again.")}
      end
    else
      {:noreply,
       assign(socket,
         phone: phone,
         phone_error: "Enter a valid M-Pesa number, e.g. 07XXXXXXXX"
       )}
    end
  end

  @impl true
  def handle_info({:payment_confirmed, enrollment}, socket) do
    if enrollment.course_id == socket.assigns.course.id do
      {:noreply, redirect(socket, to: ~p"/learn/courses/#{socket.assigns.course.slug}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_params(%{"status" => "waiting"}, _uri, socket),
    do: {:noreply, assign(socket, :waiting, true)}

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:courses} current_user={@current_user}>
      <div class="bg-gradient-to-b from-mint via-white to-soft py-16">
        <div class="mx-auto max-w-2xl px-5">
          <.link navigate={~p"/courses/#{@course.slug}"} class="text-sm font-medium text-primary">
            ← Back to course
          </.link>

          <section class="mt-6 rounded-[32px] border border-black/5 bg-white p-7 shadow-xl sm:p-10">
            <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
              Secure checkout
            </span>
            <h1 class="mt-5 text-3xl font-semibold text-dark sm:text-4xl">
              Enroll in {@course.title}
            </h1>
            <p class="mt-3 text-body">
              You will pay on Paystack's hosted checkout. Wasomi never receives or stores your card details.
            </p>

            <div class="mt-8 flex items-center justify-between rounded-2xl bg-soft p-5">
              <span class="font-medium text-dark">One-time course fee</span>
              <span class="text-2xl font-semibold text-dark">
                {Catalog.format_price(@course, assigns[:display_currency])}
              </span>
            </div>

            <p
              :if={assigns[:display_currency] && assigns[:display_currency] != "KES"}
              class="mt-2 text-sm text-zinc-500"
            >
              * Billed as KES {Catalog.price(@course) |> Money.to_string!()} at checkout.
            </p>

            <div :if={@waiting} id="payment-waiting" class="mt-6 rounded-2xl bg-mint p-5 text-body">
              Payment confirmation is still processing. You can leave this page; access will unlock
              automatically as soon as Paystack confirms it.
            </div>

            <form id="checkout-form" phx-submit="pay" class="mt-7 space-y-4">
              <div>
                <label for="checkout-phone" class="block text-sm font-medium text-dark">
                  M-Pesa phone number
                </label>
                <p class="mt-1 text-sm text-body">
                  The payment prompt will be sent to this number.
                </p>
                <input
                  id="checkout-phone"
                  name="phone"
                  type="tel"
                  value={@phone}
                  placeholder="07XXXXXXXX"
                  required
                  class="mt-2 w-full rounded-2xl border border-black/10 px-4 py-3 text-dark focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                />
                <p :if={@phone_error} class="mt-1 text-sm font-medium text-rose-600">
                  {@phone_error}
                </p>
              </div>

              <button
                id="pay-with-paystack"
                type="submit"
                disabled={@submitting}
                class="w-full rounded-full bg-dark px-6 py-4 font-medium text-white transition hover:bg-primary disabled:cursor-wait disabled:opacity-60"
              >
                {if @submitting, do: "Opening Paystack…", else: "Enroll & Pay"}
              </button>
            </form>
          </section>
        </div>
      </div>
    </.student_layout>
    """
  end

  # Logs only field-level error messages, never the changeset's raw params
  # (which would include the learner's phone number).
  defp describe_checkout_error(%Ecto.Changeset{} = changeset) do
    inspect(Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end))
  end

  defp describe_checkout_error(reason) when is_binary(reason) or is_atom(reason) do
    inspect(reason)
  end

  defp describe_checkout_error({tag, detail})
       when is_atom(tag) and (is_binary(detail) or is_integer(detail) or is_atom(detail)) do
    inspect({tag, detail})
  end

  # Anything else (maps, keyword lists, arbitrary structs) could carry
  # caller-supplied data, so log neither its shape nor its contents.
  defp describe_checkout_error(_reason), do: "unrecognized error"
end
