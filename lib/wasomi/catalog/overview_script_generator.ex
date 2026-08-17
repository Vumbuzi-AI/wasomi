defmodule Wasomi.Catalog.OverviewScriptGenerator do
  @moduledoc """
  Boundary for turning a lecture's source text (its attached document/link
  resources) into a scene-by-scene narration script for a generated video
  overview.

  Implementations return already-parsed, shape-checked data — a list of
  `%{narration: String.t(), slide_text: String.t()}` maps, one per scene —
  never raw model output. Callers never parse LLM JSON themselves. Mirrors
  `Wasomi.Assessments.QuestionGenerator`'s boundary shape.
  """

  @type scene :: %{narration: String.t(), slide_text: String.t()}

  @callback generate_script(text :: String.t(), opts :: keyword()) ::
              {:ok, [scene()]} | {:error, term()}
end
