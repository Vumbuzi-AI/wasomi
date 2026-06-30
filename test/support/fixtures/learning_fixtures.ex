defmodule Wasomi.LearningFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Learning` context.
  """

  @doc """
  Generate a lecture_progress.
  """
  def lecture_progress_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    user_id = Map.get_lazy(attrs, :user_id, fn -> Wasomi.AccountsFixtures.user_fixture().id end)

    lecture_id =
      Map.get_lazy(attrs, :lecture_id, fn -> Wasomi.CatalogFixtures.lecture_fixture().id end)

    {:ok, lecture_progress} =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:lecture_id, lecture_id)
      |> Enum.into(%{
        last_position_seconds: 42,
        status: :not_started
      })
      |> Wasomi.Learning.create_lecture_progress()

    lecture_progress
  end
end
