defmodule Wasomi.ChannelsFixtures do
  @moduledoc """
  Test helpers for `Wasomi.Channels`.
  """

  alias Wasomi.{Channels, Repo}
  alias Wasomi.Channels.Message

  @doc "Returns the channel for a course, creating it if needed."
  def channel_fixture(course), do: Channels.get_or_create_for_course(course)

  @doc """
  Inserts a message straight into a channel, bypassing the posting
  authorization checks — handy for arranging history in a test.
  """
  def channel_message_fixture(channel, user, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, message} =
      %Message{}
      |> Message.changeset(%{
        channel_id: channel.id,
        user_id: user.id,
        body: Map.get(attrs, :body, "Hello cohort"),
        kind: Map.get(attrs, :kind, :message),
        pinned_at: Map.get(attrs, :pinned_at),
        mentioned_user_ids: Map.get(attrs, :mentioned_user_ids, [])
      })
      |> Repo.insert()

    message
  end
end
