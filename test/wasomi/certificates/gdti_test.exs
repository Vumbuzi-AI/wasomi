defmodule Wasomi.Certificates.GDTITest do
  use ExUnit.Case, async: true

  alias Wasomi.Certificates.GDTI

  @company_prefix Application.compile_env!(:wasomi, :certificate_gdti)[:company_prefix]
  @document_type Application.compile_env!(:wasomi, :certificate_gdti)[:document_type]

  describe "core/0" do
    test "starts with the configured company prefix and document type" do
      assert String.starts_with?(GDTI.core(), @company_prefix <> @document_type)
    end

    test "is exactly 13 digits (12-digit base + 1 check digit), all numeric" do
      core = GDTI.core()
      assert String.length(core) == 13
      assert core =~ ~r/^\d{13}$/
    end

    test "is deterministic — same company prefix/document type always produce the same core" do
      assert GDTI.core() == GDTI.core()
    end

    test "the check digit matches an independent implementation of the GS1 Mod10 algorithm" do
      core = GDTI.core()
      {base, check_digit} = String.split_at(core, 12)

      assert check_digit == gs1_mod10_check_digit(base)
    end
  end

  describe "generate/0" do
    test "is the 13-digit core followed by a 9-digit numeric serial (22 digits total)" do
      gdti = GDTI.generate()

      assert String.length(gdti) == 22
      assert gdti =~ ~r/^\d{22}$/
      assert String.starts_with?(gdti, GDTI.core())
    end

    test "the check digit portion is still spec-correct on a generated (not just core) value" do
      gdti = GDTI.generate()
      {base, rest} = String.split_at(gdti, 12)
      check_digit = String.at(rest, 0)

      assert check_digit == gs1_mod10_check_digit(base)
    end

    test "the serial component is randomized across calls" do
      results = for _ <- 1..20, do: GDTI.generate()

      assert Enum.uniq(results) == results
    end

    test "many generations stay unique (no realistic collision at this scale)" do
      # 9 random digits ~= 1 billion combinations; 500 draws keeps the
      # birthday-paradox collision probability at ~1 in 8,000 — safely
      # non-flaky while still exercising real collision-avoidance behavior.
      results = for _ <- 1..500, do: GDTI.generate()

      assert length(Enum.uniq(results)) == 500
    end
  end

  # Independent implementation of the GS1 Mod10 check-digit algorithm (per
  # the GS1 GDTI Executive Summary), deliberately *not* reusing ExGtin's
  # own implementation — this is what actually verifies GDTI.core/0
  # against the spec, rather than just checking it's internally
  # self-consistent with the library it happens to be built on.
  #
  # Rule: starting from the rightmost base digit, alternate weights 3, 1,
  # 3, 1, ...; sum the weighted digits; the check digit is whatever value
  # (0-9) makes that sum a multiple of 10.
  defp gs1_mod10_check_digit(base_digits) do
    sum =
      base_digits
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.reduce(0, fn {digit, idx}, acc ->
        weight = if rem(idx, 2) == 0, do: 3, else: 1
        acc + digit * weight
      end)

    rem(10 - rem(sum, 10), 10) |> Integer.to_string()
  end
end
