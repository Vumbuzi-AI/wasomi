defmodule Wasomi.Repo.Migrations.AddStudentPaymentNotificationKind do
  use Ecto.Migration

  # NOTE: this branch was rebased after the course-channel notification kinds
  # (`20260830023700`) landed on main. Ecto runs this lower-versioned migration
  # last, so the CHECK it recreates must carry the channel kinds too — otherwise
  # it would silently drop `channel_announcement` / `channel_mention`.
  @with_student_payment """
  kind IN (
    'enrollment_granted',
    'student_payment',
    'reengagement_never_started', 'reengagement_never_started_2', 'reengagement_never_started_3',
    'reengagement_gone_quiet', 'reengagement_gone_quiet_2', 'reengagement_gone_quiet_3',
    'channel_announcement', 'channel_mention'
  )
  """

  @without_student_payment """
  kind IN (
    'enrollment_granted',
    'reengagement_never_started', 'reengagement_never_started_2', 'reengagement_never_started_3',
    'reengagement_gone_quiet', 'reengagement_gone_quiet_2', 'reengagement_gone_quiet_3',
    'channel_announcement', 'channel_mention'
  )
  """

  def up do
    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid,
             check: @with_student_payment
           )
  end

  def down do
    drop constraint(:notifications, :notifications_kind_must_be_valid)

    create constraint(:notifications, :notifications_kind_must_be_valid,
             check: @without_student_payment
           )
  end
end
