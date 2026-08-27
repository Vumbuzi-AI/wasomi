defmodule Wasomi.Content do
  @moduledoc """
  Admin-customizable content for otherwise-static pages — currently just the
  landing page's named image slots (`Wasomi.Content.LandingImage`).
  """

  import Ecto.Query, warn: false

  alias Wasomi.Content.LandingImage
  alias Wasomi.Repo

  @doc """
  The resolved `%{url:, alt:}` for every landing-page slot, in one query.

  Returns a `%{slot => %{url:, alt:}}` map covering every slot in
  `LandingImage.slots/0` — a slot with no admin override resolves to its
  hardcoded default image and alt text. Landing page components look up
  their own slot from this map rather than each triggering a query, so
  rendering the page costs exactly one small `landing_images` read (at
  most one row per slot) no matter how many slots it uses.
  """
  def landing_image_map do
    overrides =
      LandingImage
      |> select([li], {li.slot, {li.image_url, li.alt_text}})
      |> Repo.all()
      |> Map.new()

    Map.new(LandingImage.slots(), fn slot ->
      default = %{url: LandingImage.default_path(slot), alt: LandingImage.default_alt(slot)}

      resolved =
        case Map.get(overrides, slot) do
          {url, alt} -> %{url: url, alt: alt || LandingImage.default_alt(slot)}
          nil -> default
        end

      {slot, resolved}
    end)
  end

  @doc """
  The resolved image URL for a single slot — the admin override if one
  exists, otherwise the hardcoded default. Prefer `landing_image_map/0` when
  resolving more than one slot (e.g. rendering the whole landing page).
  """
  def image_url_for(slot) when is_atom(slot) do
    true = slot in LandingImage.slots()

    case Repo.get_by(LandingImage, slot: slot) do
      %LandingImage{image_url: url} -> url
      nil -> LandingImage.default_path(slot)
    end
  end

  @doc """
  Every defined slot for the admin listing page: `slot`, `label`,
  `default_path`, the currently-resolved `image_url`/`alt_text`, and
  whether that's an override (`overridden?`).
  """
  def list_landing_image_slots do
    overrides =
      LandingImage
      |> select([li], {li.slot, {li.image_url, li.alt_text}})
      |> Repo.all()
      |> Map.new()

    Enum.map(LandingImage.slots(), fn slot ->
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
  Sets (or replaces) the admin override for `slot` — `image_url` required,
  `alt_text` optional (falls back to the slot's default alt text when
  blank/omitted).
  """
  def put_landing_image(slot, image_url, alt_text \\ nil) do
    %LandingImage{}
    |> LandingImage.changeset(%{slot: slot, image_url: image_url, alt_text: alt_text})
    |> Repo.insert(
      on_conflict: {:replace, [:image_url, :alt_text, :updated_at]},
      conflict_target: :slot
    )
  end

  @doc """
  Clears any admin override for `slot`, so it falls back to its hardcoded
  default. Safe to call for a slot with no override (no-op).
  """
  def reset_landing_image(slot) do
    LandingImage
    |> where([li], li.slot == ^slot)
    |> Repo.delete_all()

    :ok
  end
end
