defmodule Wasomi.Certificates.GDTI do
  @moduledoc """
  Generates GS1 GDTI (Global Document Type Identifier) values for
  certificates, per the decisions recorded in TODO.md's GDTI section: the
  GDTI is the certificate's sole identifier (no separate serial number),
  and one document-type code covers both module and course certificates.

  Structure, per the GS1 GDTI Executive Summary:
    - GS1 Company Prefix + Document Type = a 12-digit base, always exactly
      12 digits regardless of how long the prefix itself is.
    - + 1 check digit (the standard GS1 Mod10 checksum: alternating
      weights of 3 and 1, starting from the rightmost base digit) = a
      13-digit GDTI core.
    - + a serial component (numeric here; up to 17 characters allowed by
      spec, 9 used here) distinguishing individual documents of the same
      type. 9 random digits (~1 billion combinations) keeps collision risk
      negligible well past the certificate volume this platform expects,
      without running noticeably longer than GS1 Kenya's own real-world
      GDTI examples.

  The 13-digit core is generated via `ExGtin.generate!/1`. Its check-digit
  algorithm was verified by reading the package's source directly
  (`ExGtin.Validation.multiply_and_sum_array/1` and
  `mult_by_index_code/1`): weight 3 on the rightmost base digit,
  alternating with weight 1, matching the GS1-standard Mod10 algorithm
  exactly — the same one used for GTIN, GLN, SSCC, and GDTI alike. The
  library only *labels* a 13-digit result "GTIN-13" internally; that label
  is irrelevant here since generation never calls `validate/1`.
  """

  @serial_digits 9

  @doc """
  Generates a new, structurally valid GDTI with a random serial component.

  Returns the full identifier as a string: the 13-digit GDTI core followed
  immediately by a #{@serial_digits}-digit random serial, with no
  separators — matching the format GS1 Kenya's own certificate-
  verification system uses.
  """
  @spec generate() :: String.t()
  def generate, do: core() <> random_serial()

  @doc """
  The 13-digit GDTI core (company prefix + document type + check digit),
  without a serial component. Exposed so tests can verify the check digit
  independently of the random serial.
  """
  @spec core() :: String.t()
  def core do
    config = Application.fetch_env!(:wasomi, :certificate_gdti)
    ExGtin.generate!(config[:company_prefix] <> config[:document_type])
  end

  defp random_serial do
    bound = 10 ** @serial_digits

    :crypto.strong_rand_bytes(8)
    |> :binary.decode_unsigned()
    |> rem(bound)
    |> Integer.to_string()
    |> String.pad_leading(@serial_digits, "0")
  end
end
