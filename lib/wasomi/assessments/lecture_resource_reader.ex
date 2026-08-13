defmodule Wasomi.Assessments.LectureResourceReader do
  @moduledoc """
  Behaviour for turning a lecture's non-video resource into text a
  `Wasomi.Assessments.QuestionGenerator` can draft questions from.

  Swappable via the `:lecture_resource_reader` config key, same pattern as
  `:pdf_extractor`/`:question_generator` — tests point at
  `Wasomi.LectureResourceReaderMock`.
  """

  @callback extract_text(Wasomi.Catalog.LectureResource.t()) ::
              {:ok, String.t()} | {:error, term()}
end
