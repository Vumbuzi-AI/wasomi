defmodule Wasomi.Assessments.StudyGuideGenerator do
  @moduledoc """
  Boundary for turning course material into a written study guide.

  Distinct from the question generators: nothing here is assessed. The output
  is a document a learner reads — retold in the style they asked for, at the
  depth and reading level they asked for, optionally narrowed to their own
  free-text focus.

  Implementations return already-parsed, shape-checked data — never raw model
  output, and never markup. Callers never parse LLM JSON themselves.
  """

  @type draft_section :: %{
          heading: String.t(),
          body: String.t() | nil,
          bullets: [String.t()],
          callout: String.t() | nil
        }

  @type draft_term :: %{term: String.t(), definition: String.t()}

  @type draft_guide :: %{
          title: String.t() | nil,
          summary: String.t() | nil,
          sections: [draft_section()],
          key_takeaways: [String.t()],
          key_terms: [draft_term()]
        }

  @doc """
  Options:

    * `:style` — `:story | :notes | :cheat_sheet | :q_and_a | :analogies`
    * `:depth` — `:brief | :standard | :deep`
    * `:reading_level` — `:beginner | :intermediate | :advanced`
    * `:include_key_terms` — add a glossary of the terms the material relies on
    * `:include_examples` — work a concrete example into each section
    * `:focus` — the learner's own instruction, or `nil`
    * `:scope_label` — what the material is called, for the document's title
  """
  @callback generate_guide(text :: String.t(), opts :: keyword()) ::
              {:ok, draft_guide()} | {:error, term()}
end
