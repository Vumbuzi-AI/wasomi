defmodule WasomiWeb.Presence do
  @moduledoc """
  Presence tracking. Currently used by course cohort channels to show how
  many members are viewing a channel right now.
  """
  use Phoenix.Presence,
    otp_app: :wasomi,
    pubsub_server: Wasomi.PubSub
end
