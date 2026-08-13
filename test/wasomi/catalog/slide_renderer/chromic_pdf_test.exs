defmodule Wasomi.Catalog.SlideRenderer.ChromicPdfTest do
  use ExUnit.Case, async: true

  alias Wasomi.Catalog.SlideRenderer.ChromicPdf

  test "returns {:error, reason} instead of crashing when ChromicPDF isn't running" do
    # Mirrors Wasomi.Certificates.Renderer.ChromicPdfTest: ChromicPDF is
    # deliberately not started in test (config/test.exs sets
    # start_chromic_pdf: false), exercising the same real failure path a
    # crashed/unavailable browser would also hit.
    assert {:error, _reason} = ChromicPdf.render("Step one")
  end
end
