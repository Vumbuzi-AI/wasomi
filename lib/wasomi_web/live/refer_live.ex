defmodule WasomiWeb.ReferLive do
  @moduledoc """
  Learner referral page: the shareable link and a plain-language funnel
  summary. No rewards, gifts, or balances (see
  PLANNING_STUDENT_REFERRALS_REWARDS.md).
  """

  use WasomiWeb, :live_view

  alias Wasomi.Referrals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Refer a friend")
     |> assign(:link, Referrals.link_for(user))
     |> assign(:stats, Referrals.stats_for(user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.student_layout active={:refer} current_user={@current_user}>
      <div class="mx-auto max-w-3xl px-5 py-8 lg:px-8">
        <.learner_page_header eyebrow="Referrals" title="Refer a friend to Wasomi">
          <:subtitle>
            Share your link with someone who'd get value from Wasomi. When they sign up through
            it, we'll credit the referral to you.
          </:subtitle>
        </.learner_page_header>

        <div class="mt-8 rounded-3xl border border-black/5 bg-white p-6 shadow-card sm:p-8">
          <div>
            <label class="text-sm font-semibold text-ink">Your referral link</label>
            <div class="mt-2 flex flex-col gap-2 sm:flex-row">
              <input
                type="text"
                readonly
                value={@link}
                class="w-full rounded-lg border border-black/15 bg-surface px-3.5 py-3 font-medium text-dark focus:outline-none"
              />
              <button
                type="button"
                id="copy-referral-link"
                phx-hook="CopyToClipboard"
                data-copy={@link}
                data-label="Copy link"
                data-done="Copied!"
                class="shrink-0 rounded-lg bg-ink px-5 py-3 font-semibold text-white transition hover:bg-primary"
              >
                Copy link
              </button>
            </div>
          </div>
        </div>

        <div class="mt-6 grid gap-4 sm:grid-cols-2">
          <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <p class="text-3xl font-bold text-ink">{@stats.confirmed}</p>
            <p class="mt-1 text-sm text-muted">friends joined</p>
          </div>
          <div class="rounded-3xl border border-black/5 bg-white p-6 shadow-card">
            <p class="text-3xl font-bold text-ink">{@stats.converted}</p>
            <p class="mt-1 text-sm text-muted">started learning</p>
          </div>
        </div>

        <p :if={@stats.signups > @stats.confirmed} class="mt-4 text-sm text-muted">
          {@stats.signups - @stats.confirmed} more haven't confirmed their email yet.
        </p>
      </div>
    </.student_layout>
    """
  end
end
