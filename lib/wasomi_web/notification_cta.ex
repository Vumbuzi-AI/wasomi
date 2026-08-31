defmodule WasomiWeb.NotificationCTA do
  @moduledoc """
  Shared call-to-action resolution for a notification row, used by both the
  learner (`NotificationsLive`) and admin (`AdminLive.Notifications`) inboxes.

  The notification data is role-agnostic; only the destination shell differs,
  so `destination/2` takes an `admin?` flag and routes into the matching area.
  """

  use WasomiWeb, :verified_routes

  @channel_kinds [:channel_announcement, :channel_mention]

  @doc "Button label for a notification's CTA."
  def label(%{kind: kind}) when kind in @channel_kinds, do: "Open discussion"
  def label(_notification), do: "Go to course"

  @doc """
  Where a notification's CTA should navigate. Admins aren't enrolled, so a
  channel notification points them at the admin discussions hub rather than
  the learner course player (which would bounce them to checkout).
  """
  def destination(%{kind: kind} = notification, true) when kind in @channel_kinds do
    ~p"/admin/discussions?#{channel_params(notification, %{course: notification.course.slug})}"
  end

  def destination(%{kind: kind} = notification, false) when kind in @channel_kinds do
    ~p"/learn/courses/#{notification.course.slug}?#{channel_params(notification, %{tab: "discussion"})}"
  end

  def destination(%{course: %{slug: slug}}, true), do: ~p"/admin/courses/#{slug}"
  def destination(%{course: %{slug: slug}}, false), do: ~p"/learn/courses/#{slug}"

  defp channel_params(%{channel_message_id: nil}, base), do: base
  defp channel_params(%{channel_message_id: msg_id}, base), do: Map.put(base, :msg, msg_id)
end
