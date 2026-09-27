defmodule WasomiWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use WasomiWeb, :html

  embed_templates "error_html/*"

  # Any status without its own template above (e.g. 400 on a CSRF failure,
  # 401, 405, 422) still gets the branded card, just with a generic
  # heading derived from the status code instead of bespoke copy.
  def render(template, _assigns) do
    case template |> String.split(".") |> hd() |> Integer.parse() do
      {code, ""} ->
        error_card(%{
          code: to_string(code),
          heading: Plug.Conn.Status.reason_phrase(code),
          description: "Something didn't go as expected. If this keeps happening, let us know."
        })

      _ ->
        Phoenix.Controller.status_message_from_template(template)
    end
  end

  attr :code, :string, required: true
  attr :heading, :string, required: true
  attr :description, :string, required: true

  defp error_card(assigns) do
    assigns = Map.put(assigns, :support_email, Application.get_env(:wasomi, :support_email))

    ~H"""
    <div class="relative flex min-h-screen items-center justify-center overflow-hidden bg-surface px-6 py-16">
      <div class="pointer-events-none absolute -left-24 -top-24 h-72 w-72 rounded-full bg-primary/10 blur-3xl">
      </div>
      <div class="pointer-events-none absolute -bottom-24 -right-24 h-72 w-72 rounded-full bg-ink/10 blur-3xl">
      </div>

      <div class="relative w-full max-w-lg rounded-3xl border border-black/5 bg-white p-10 text-center shadow-card sm:p-14">
        <a href={~p"/"} class="inline-flex">
          <img src="/images/logo.png" alt="Wasomi" class="h-8 w-auto" />
        </a>

        <p class="mt-8 text-6xl font-extrabold tracking-tight text-primary sm:text-7xl">
          {@code}
        </p>
        <h1 class="mt-3 text-xl font-bold text-ink sm:text-2xl">{@heading}</h1>
        <p class="mx-auto mt-3 max-w-sm text-body">{@description}</p>

        <div class="mt-8 flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
          <a
            href={~p"/"}
            class="group inline-flex items-center gap-2 rounded-full bg-primary py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-ink"
          >
            Go to homepage
            <span class="grid h-9 w-9 place-items-center rounded-full bg-white text-primary transition group-hover:bg-ink group-hover:text-white">
              <svg
                class="h-4 w-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
              </svg>
            </span>
          </a>
          <a
            href={"mailto:#{@support_email}"}
            class="inline-flex items-center justify-center rounded-full border border-black/10 px-6 py-3 text-sm font-medium text-ink transition hover:border-ink/30"
          >
            Contact support
          </a>
        </div>
      </div>
    </div>
    """
  end
end
