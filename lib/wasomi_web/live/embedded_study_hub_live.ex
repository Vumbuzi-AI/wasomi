defmodule WasomiWeb.EmbeddedStudyHubLive do
  @moduledoc """
  Router-free host for the Study UI inside the course workspace.

  The routed Study LiveView owns the implementation. This small host delegates
  its callbacks without exporting `handle_params/3`, which Phoenix does not
  permit on a nested LiveView.
  """

  use WasomiWeb, :live_view

  alias WasomiWeb.StudyHubLive

  @impl true
  defdelegate mount(params, session, socket), to: StudyHubLive

  @impl true
  defdelegate render(assigns), to: StudyHubLive

  @impl true
  defdelegate handle_event(event, params, socket), to: StudyHubLive

  @impl true
  defdelegate handle_info(message, socket), to: StudyHubLive
end
