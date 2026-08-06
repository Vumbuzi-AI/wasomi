defmodule Wasomi.LearningFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Wasomi.Learning` context.
  """

  import Ecto.Query

  @doc """
  Completes a lecture via real `record_progress/3` calls (not a raw insert),
  so completion side effects still fire. Backdates the intermediate save so
  the jump to full duration isn't rejected by the anti-cheat clamp.
  """
  def complete_lecture_via_progress!(user, lecture) do
    {:ok, _progress, _events} = Wasomi.Learning.record_progress(user, lecture, 1)

    Wasomi.Learning.LectureProgress
    |> where([p], p.user_id == ^user.id and p.lecture_id == ^lecture.id)
    |> Wasomi.Repo.update_all(
      set: [
        updated_at:
          DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      ]
    )

    Wasomi.Learning.record_progress(user, lecture, lecture.duration_seconds)
  end

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
