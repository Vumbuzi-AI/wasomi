defmodule Wasomi.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @reengagement_kinds [
    :reengagement_never_started,
    :reengagement_never_started_2,
    :reengagement_never_started_3,
    :reengagement_gone_quiet,
    :reengagement_gone_quiet_2,
    :reengagement_gone_quiet_3
  ]
  @channel_kinds [:channel_announcement, :channel_mention]
  @course_scoped_kinds @reengagement_kinds ++ @channel_kinds

  schema "notifications" do
    field :kind, Ecto.Enum, values: [:enrollment_granted] ++ @reengagement_kinds ++ @channel_kinds

    field :title, :string
    field :body, :string
    field :read_at, :utc_datetime
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course
    belongs_to :channel_message, Wasomi.Channels.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:kind, :title, :body, :read_at, :user_id, :course_id, :channel_message_id])
    |> validate_required([:kind, :title, :body, :user_id])
    |> validate_course_scoped_kind()
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
    |> assoc_constraint(:channel_message)
    |> unique_constraint([:user_id, :course_id, :kind],
      name: :notifications_user_id_course_id_kind_index
    )
  end

  # The re-engagement kinds are per-enrollment nudges: a `course_id` is what
  # lets `Wasomi.Notifications`' unique index (user_id, course_id, kind)
  # scope its idempotency check to "this learner, this course", not just
  # "this learner, this kind".
  defp validate_course_scoped_kind(changeset) do
    if get_field(changeset, :kind) in @course_scoped_kinds do
      validate_required(changeset, [:course_id])
    else
      changeset
    end
  end
end
