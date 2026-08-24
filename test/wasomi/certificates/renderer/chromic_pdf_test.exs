defmodule Wasomi.Certificates.Renderer.ChromicPdfTest do
  use ExUnit.Case, async: true

  alias Wasomi.Certificates.Renderer.ChromicPdf

  @assigns %{
    learner_name: "Jane Sample",
    title: "Sample Course",
    issued_on: "August 4, 2026",
    serial_number: "SAMPLE-0000"
  }

  test "returns {:error, reason} instead of crashing when ChromicPDF isn't running" do
    # ChromicPDF is deliberately not started in test (config/test.exs sets
    # start_chromic_pdf: false), so this exercises the real failure path a
    # crashed/unavailable browser would also hit.
    assert {:error, %RuntimeError{}} = ChromicPdf.render(@assigns)
  end
end
