defmodule Wasomi.Content do
  @moduledoc """
  Admin-customizable content for otherwise-static pages — currently just the
  landing page's named image slots (`Wasomi.Content.LandingImage`).
  """

  import Ecto.Query, warn: false

  alias Wasomi.Content.LandingImage
  alias Wasomi.Repo

  @doc """
  The resolved images for every landing-page slot, in one query.

  Returns `%{slot => %{url:, alt:}}` for every single-image slot, and
  `%{hero: [%{url:, alt:}, ...]}` for the multi-image slot — at least one
  entry, falling back to the hardcoded default when there's no override.
  """
  def landing_image_map do
    rows =
      LandingImage
      |> order_by([li], asc: li.position)
      |> select([li], {li.slot, li.image_url, li.alt_text})
      |> Repo.all()

    {hero_rows, single_rows} =
      Enum.split_with(rows, fn {slot, _, _} -> slot == LandingImage.multi_slot() end)

    single_overrides = Map.new(single_rows, fn {slot, url, alt} -> {slot, {url, alt}} end)

    singles =
      Map.new(LandingImage.slots() -- [LandingImage.multi_slot()], fn slot ->
        resolved =
          case Map.get(single_overrides, slot) do
            {url, alt} -> %{url: url, alt: alt || LandingImage.default_alt(slot)}
            nil -> %{url: LandingImage.default_path(slot), alt: LandingImage.default_alt(slot)}
          end

        {slot, resolved}
      end)

    Map.put(singles, LandingImage.multi_slot(), hero_images(hero_rows))
  end

  defp hero_images([]) do
    [%{url: LandingImage.default_path(:hero), alt: LandingImage.default_alt(:hero)}]
  end

  defp hero_images(rows) do
    Enum.map(rows, fn {_slot, url, alt} -> %{url: url, alt: alt || ""} end)
  end

  @doc """
  The resolved image URL for a single-image slot — the admin override if
  one exists, otherwise the hardcoded default. Not meaningful for
  `LandingImage.multi_slot/0`, which can have several rows; use
  `list_hero_images/0` for that one.
  """
  def image_url_for(slot) when is_atom(slot) do
    true = slot in LandingImage.slots()

    case Repo.get_by(LandingImage, slot: slot) do
      %LandingImage{image_url: url} -> url
      nil -> LandingImage.default_path(slot)
    end
  end

  @doc """
  Every single-image slot for the admin listing page: `slot`, `label`,
  `default_path`, the currently-resolved `image_url`/`alt_text`, and
  whether that's an override (`overridden?`). Excludes
  `LandingImage.multi_slot/0` — see `list_hero_images/0`.
  """
  def list_landing_image_slots do
    overrides =
      LandingImage
      |> where([li], li.slot != ^LandingImage.multi_slot())
      |> select([li], {li.slot, {li.image_url, li.alt_text}})
      |> Repo.all()
      |> Map.new()

    Enum.map(LandingImage.slots() -- [LandingImage.multi_slot()], fn slot ->
      default = LandingImage.default_path(slot)
      override = Map.get(overrides, slot)
      {override_url, override_alt} = override || {nil, nil}

      %{
        slot: slot,
        label: LandingImage.label(slot),
        default_path: default,
        image_url: override_url || default,
        alt_text: override_alt || LandingImage.default_alt(slot),
        overridden?: not is_nil(override)
      }
    end)
  end

  @doc """
  Sets (or replaces) the admin override for a single-image `slot` —
  `image_url` required, `alt_text` optional (falls back to the slot's
  default alt text when blank/omitted). Not for
  `LandingImage.multi_slot/0` — see `add_hero_image/2`.
  """
  def put_landing_image(slot, image_url, alt_text \\ nil) do
    %LandingImage{}
    |> LandingImage.changeset(%{slot: slot, image_url: image_url, alt_text: alt_text})
    |> Repo.insert(
      on_conflict: {:replace, [:image_url, :alt_text, :updated_at]},
      # `landing_images_single_slot_index` is partial (`WHERE slot != 'hero'`);
      # Postgres needs that exact predicate here to match it as the conflict target.
      conflict_target: {:unsafe_fragment, "(slot) WHERE ((slot)::text <> 'hero'::text)"}
    )
  end

  @doc """
  Clears any admin override for a single-image `slot`, so it falls back to
  its hardcoded default. Safe to call for a slot with no override (no-op).
  """
  def reset_landing_image(slot) do
    LandingImage
    |> where([li], li.slot == ^slot)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Every hero image, in display order, as `%{id:, url:, alt:, position:}` —
  the admin editor's list-management view. Empty when no overrides exist
  (the public page falls back to the single hardcoded default in that
  case — see `landing_image_map/0`).
  """
  def list_hero_images do
    LandingImage
    |> where([li], li.slot == ^LandingImage.multi_slot())
    |> order_by([li], asc: li.position)
    |> select([li], %{id: li.id, url: li.image_url, alt: li.alt_text, position: li.position})
    |> Repo.all()
  end

  @doc """
  Appends a new hero image at the end of the order. Fails with
  `{:error, :limit_reached}` at `LandingImage.multi_slot_max/0` images
  rather than a changeset error — this is a capacity check, not a
  validation of the submitted data.
  """
  def add_hero_image(image_url, alt_text \\ nil) do
    count = hero_count()

    if count >= LandingImage.multi_slot_max() do
      {:error, :limit_reached}
    else
      %LandingImage{}
      |> LandingImage.changeset(%{
        slot: LandingImage.multi_slot(),
        image_url: image_url,
        alt_text: alt_text,
        position: count
      })
      |> Repo.insert()
    end
  end

  defp hero_count do
    LandingImage
    |> where([li], li.slot == ^LandingImage.multi_slot())
    |> Repo.aggregate(:count)
  end

  @doc """
  Removes one hero image by id, then closes the gap in `:position` left
  behind so positions stay a contiguous 0..n-1 (what `add_hero_image/2`
  relies on to pick the next slot).
  """
  def remove_hero_image(id) do
    Repo.transaction(fn ->
      case Repo.get(LandingImage, id) do
        %LandingImage{slot: slot} = image when slot == :hero ->
          Repo.delete!(image)
          close_position_gap(image.position)
          :ok

        _ ->
          Repo.rollback(:not_found)
      end
    end)
  end

  defp close_position_gap(removed_position) do
    LandingImage
    |> where([li], li.slot == ^LandingImage.multi_slot() and li.position > ^removed_position)
    |> Repo.update_all(inc: [position: -1])
  end

  @doc """
  Swaps a hero image with its neighbor in the given `direction`
  (`:up`/`:down`). A no-op (returns `:ok`) if it's already at that end of
  the list.
  """
  def move_hero_image(id, direction) when direction in [:up, :down] do
    images = list_hero_images()

    case Enum.find_index(images, &(&1.id == id)) do
      nil ->
        {:error, :not_found}

      index ->
        neighbor_index = if direction == :up, do: index - 1, else: index + 1
        neighbor = Enum.at(images, neighbor_index)
        current = Enum.at(images, index)

        if neighbor do
          swap_positions(current, neighbor)
        else
          :ok
        end
    end
  end

  # The (slot, position) unique index is checked per-statement, so park `a`
  # at an unused position (-1) before the swap to avoid colliding with `b`.
  defp swap_positions(a, b) do
    Repo.transaction(fn ->
      set_position!(a.id, -1)
      set_position!(b.id, a.position)
      set_position!(a.id, b.position)
    end)

    :ok
  end

  defp set_position!(id, position) do
    Repo.get!(LandingImage, id) |> Ecto.Changeset.change(position: position) |> Repo.update!()
  end
end
