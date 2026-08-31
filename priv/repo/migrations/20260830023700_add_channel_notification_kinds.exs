defmodule Wasomi.Repo.Migrations.AddChannelNotificationKinds do
  use Ecto.Migration

  @all_kinds """
  kind IN (
    'enrollment_granted',
    'reengagement_never_started', 'reengagement_never_started_2', 'reengagement_never_started_3',
    'reengagement_gone_quiet', 'reengagement_gone_quiet_2', 'reengagement_gone_quiet_3',
    'channel_announcement', 'channel_mention'
  )
  """

  @previous_kinds """
  kind IN (
    'enrollment_granted',
    'reengagement_never_started', 'reengagement_never_started_2', 'reengagement_never_started_3',
    'reengagement_gone_quiet', 'reengagement_gone_quiet_2', 'reengagement_gone_quiet_3'
  )
  """

  # Channel announcements and mentions are repeatable per (user, course), so
  # they're carved out of the idempotency unique index that the re-engagement
  # nudges rely on.
  @repeatable "kind NOT IN ('channel_announcement', 'channel_mention')"

  def up do
    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid, check: @all_kinds)

    drop unique_index(:notifications, [:user_id, :course_id, :kind])

    create unique_index(:notifications, [:user_id, :course_id, :kind], where: @repeatable)
  end

  def down do
    drop unique_index(:notifications, [:user_id, :course_id, :kind], where: @repeatable)

    create unique_index(:notifications, [:user_id, :course_id, :kind])

    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid, check: @previous_kinds)
  end
end
