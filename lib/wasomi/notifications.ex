defmodule Wasomi.Notifications do
  @moduledoc """
  Entry point for transactional notifications.

  Delivery is synchronous for the proof-of-concept. Phase 9 can move this
  boundary behind Oban without changing callers in the domain contexts.
  """

  alias Wasomi.Accounts.{User, UserNotifier}

  @doc """
  Sends the welcome message after a learner confirms their account.

  Confirmation remains successful if the mail provider is temporarily
  unavailable; later notification work can add durable retries.
  """
  def deliver_welcome(%User{} = user) do
    UserNotifier.deliver_welcome(user)
  end
end
