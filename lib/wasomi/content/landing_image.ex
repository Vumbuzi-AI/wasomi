defmodule Wasomi.Content.LandingImage do
  @moduledoc """
  An admin-uploaded override for one named image slot on the public landing
  page (`WasomiWeb.HomeComponents`).

  Slots are a fixed, closed set — not a general page-builder — matching the
  images actually hardcoded in `home_components.ex` at the time this was
  built: the hero banner and the four "See GS1 in action" step visuals.
  Every slot has a hardcoded default path (`default_path/1`) so the landing
  page renders identically to today when no row exists for a slot; a row
  here only ever *overrides* that default.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @slots [
    :hero,
    :gs1_step_identify,
    :gs1_step_capture,
    :gs1_step_share,
    :gs1_step_verify
  ]

  @defaults %{
    hero: "/images/hero-home.png",
    gs1_step_identify: "/images/gs1-box.png",
    gs1_step_capture: "/images/hero-home.png",
    gs1_step_share: "/images/hero_image.jpg",
    gs1_step_verify: "/images/auth-learning-bg.jpg"
  }

  @labels %{
    hero: "Hero banner",
    gs1_step_identify: "\"See GS1 in action\" — Step 01 Identify",
    gs1_step_capture: "\"See GS1 in action\" — Step 02 Capture",
    gs1_step_share: "\"See GS1 in action\" — Step 03 Share",
    gs1_step_verify: "\"See GS1 in action\" — Step 04 Verify"
  }

  # hero is decorative/aria-hidden, so it has no meaningful alt text
  @default_alts %{
    hero: "",
    gs1_step_identify: "Product labelled with a GS1 barcode",
    gs1_step_capture: "Scanning a barcode to capture product data",
    gs1_step_share: "Trading partners sharing product data",
    gs1_step_verify: "Verifying a product along its journey"
  }

  @type t :: %__MODULE__{}

  schema "landing_images" do
    field :slot, Ecto.Enum, values: @slots
    field :image_url, :string
    field :alt_text, :string
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc "The fixed list of overridable landing-page image slots."
  def slots, do: @slots

  @doc "The only slot that can hold more than one image."
  def multi_slot, do: :hero

  @doc "Max images allowed for `multi_slot/0`."
  def multi_slot_max, do: 5

  @doc "The hardcoded fallback path for `slot`, used when no override exists."
  def default_path(slot) when slot in @slots, do: Map.fetch!(@defaults, slot)

  @doc "The hardcoded fallback alt text for `slot`, used when no override exists."
  def default_alt(slot) when slot in @slots, do: Map.fetch!(@default_alts, slot)

  @doc "Human-readable label for `slot`, for the admin slot list."
  def label(slot) when slot in @slots, do: Map.fetch!(@labels, slot)

  @doc false
  def changeset(landing_image, attrs) do
    landing_image
    |> cast(attrs, [:slot, :image_url, :alt_text, :position])
    |> validate_required([:slot, :image_url])
    |> validate_length(:alt_text, max: 255)
    |> validate_inclusion(:slot, @slots)
    |> unique_constraint(:slot, name: :landing_images_single_slot_index)
    |> unique_constraint([:slot, :position])
  end
end
