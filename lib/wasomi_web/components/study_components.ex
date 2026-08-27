defmodule WasomiWeb.StudyComponents do
  @moduledoc """
  Shared self-study review UI — quiz-taking (untimed and timed), flashcard
  review, practice-question self-check, the Smart Test builder/runner, and the
  Study guide brief/document — used by both `CoursePlayerLive` (the untimed
  Module Quiz panel) and `WasomiWeb.StudyHubLive` (Flashcards, Extra practice,
  Smart Test, and Study guide). Imported locally by each, not globally, since
  only these two LiveViews need it.
  """
  use Phoenix.Component

  alias Wasomi.Assessments
  alias Wasomi.Catalog.CourseModule
  alias Wasomi.Catalog.Lecture

  import WasomiWeb.CoreComponents, only: [icon: 1]

  def format_seconds(total_seconds) do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end

  attr :current_quiz, :map, required: true
  attr :quiz_result, :any, default: nil
  attr :quiz_answers, :map, required: true
  attr :current_question_index, :integer, required: true
  attr :select_option_event, :string, default: "select-quiz-option"
  attr :submit_event, :string, default: "submit-quiz"
  attr :retake_event, :string, default: "retake-quiz"
  attr :next_event, :string, default: "next-question"
  attr :prev_event, :string, default: "prev-question"
  attr :countdown, :map, default: nil
  attr :time_expired?, :boolean, default: false

  def quiz_taking_panel(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 pb-6">
        <div>
          <span class="inline-flex items-center gap-2 rounded-full bg-mint px-3 py-1 text-xs font-semibold uppercase tracking-wider text-primary">
            <.icon name="hero-academic-cap" class="h-4 w-4" />
            Module {@current_quiz.module.position} Quiz
          </span>
          <h2 class="mt-2 text-2xl font-semibold tracking-tight text-ink">
            {@current_quiz.module.title}
          </h2>
          <p class="mt-1 text-sm text-muted">
            Passing requirement:
            <span class="font-semibold text-primary">
              {@current_quiz.quiz.passing_score_percent}% score
            </span>
          </p>
        </div>
        <div :if={@countdown && !@quiz_result} class="text-right">
          <p class="text-xs font-medium uppercase tracking-wider text-muted">Time left</p>
          <p
            id="quiz-countdown"
            phx-hook="QuizCountdown"
            phx-update="ignore"
            data-deadline={DateTime.to_iso8601(@countdown.deadline)}
            data-total-seconds={@countdown.total_seconds}
            class="text-2xl font-bold tabular-nums text-primary"
          >
            {format_seconds(@countdown.total_seconds)}
          </p>
        </div>
      </div>

      <%= if @quiz_result do %>
        <div class={[
          "mt-8 rounded-2xl p-6 text-center sm:p-8",
          if(result_passed?(@quiz_result), do: "bg-mint", else: "bg-red-50")
        ]}>
          <div class={[
            "mx-auto flex h-16 w-16 items-center justify-center rounded-full",
            if(result_passed?(@quiz_result),
              do: "bg-white text-primary",
              else: "bg-white text-red-600"
            )
          ]}>
            <.icon
              name={
                if(result_passed?(@quiz_result),
                  do: "hero-check-circle",
                  else: "hero-x-circle"
                )
              }
              class="h-8 w-8"
            />
          </div>

          <h3 class="mt-4 text-2xl font-bold text-ink">
            {cond do
              @time_expired? -> "Time's up!"
              result_passed?(@quiz_result) -> "Quiz Passed!"
              true -> "Quiz Not Passed"
            end}
          </h3>
          <p class={[
            "mt-2 text-3xl font-extrabold",
            if(result_passed?(@quiz_result), do: "text-primary", else: "text-red-600")
          ]}>
            {result_score(@quiz_result)}%
          </p>

          <p :if={preview_result?(@quiz_result)} class="mt-3 text-xs text-muted">
            Admin Preview Result — score was evaluated in-memory and not saved.
          </p>

          <div class="mt-6 flex justify-center gap-4">
            <button
              type="button"
              phx-click={@retake_event}
              class="rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-ink hover:text-white"
            >
              Retake Quiz
            </button>
          </div>
        </div>
      <% else %>
        <% question = Enum.at(@current_quiz.questions, @current_question_index) %>
        <% total = length(@current_quiz.questions) %>
        <% last_question? = @current_question_index == total - 1 %>
        <form phx-submit={@submit_event} class="mt-8 space-y-6">
          <div class="h-1.5 overflow-hidden rounded-full bg-mint">
            <div
              class="h-full rounded-full bg-primary transition-all duration-300"
              style={"width: #{round((@current_question_index + 1) / total * 100)}%"}
            >
            </div>
          </div>

          <div class="min-h-[480px] rounded-2xl border border-black/5 p-6">
            <p class="text-xs font-semibold uppercase tracking-wider text-primary">
              Question {@current_question_index + 1} of {total}
            </p>
            <h3 class="mt-2 text-lg font-medium leading-snug text-ink">
              {question.prompt}
            </h3>

            <div class="mt-4 space-y-2.5">
              <label
                :for={option <- question.question_options}
                class={[
                  "flex items-center gap-3 rounded-xl border p-3.5 transition cursor-pointer",
                  if(
                    to_string(Map.get(@quiz_answers, to_string(question.id))) ==
                      to_string(option.id),
                    do: "border-primary bg-mint text-ink font-medium",
                    else: "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40"
                  )
                ]}
              >
                <input
                  type="radio"
                  name={"question_#{question.id}"}
                  value={option.id}
                  checked={
                    to_string(Map.get(@quiz_answers, to_string(question.id))) ==
                      to_string(option.id)
                  }
                  phx-click={@select_option_event}
                  phx-value-question-id={question.id}
                  phx-value-option-id={option.id}
                  class="h-4 w-4 border-black/20 bg-white text-primary focus:ring-primary"
                />
                <span class="text-sm">{option.label}</span>
              </label>
            </div>
          </div>

          <div class="flex items-center justify-between border-t border-black/5 pt-6">
            <button
              type="button"
              phx-click={@prev_event}
              disabled={@current_question_index == 0}
              class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-mint disabled:cursor-not-allowed disabled:opacity-40"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
            </button>

            <span class="text-xs text-muted">
              Answered {map_size(@quiz_answers)} of {total} questions
            </span>

            <button
              :if={!last_question?}
              type="button"
              phx-click={@next_event}
              class="inline-flex items-center gap-1.5 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
            >
              Next <.icon name="hero-arrow-right" class="h-4 w-4" />
            </button>

            <button
              :if={last_question?}
              type="submit"
              disabled={map_size(@quiz_answers) < total}
              class="rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
            >
              Submit Quiz
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  attr :flashcard_set, :map, required: true
  attr :flashcard_cards, :list, required: true
  attr :flashcard_index, :integer, required: true
  attr :flashcard_flipped?, :boolean, required: true
  attr :module, :map, required: true
  attr :scope, :map, required: true

  def flashcard_set_panel(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <%= case @flashcard_set.status do %>
        <% :pending -> %>
          <.flashcard_setup module={@module} scope={@scope} />
        <% :processing -> %>
          <div class="flex items-center gap-4 rounded-3xl border border-primary/20 bg-mint/40 p-6">
            <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-primary shadow-sm">
              <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin" />
            </span>
            <div>
              <p class="font-semibold text-ink">Generating your flashcards…</p>
              <p class="mt-0.5 text-sm text-body">
                We're reading your lessons and drafting flashcards with AI. This usually
                takes a minute or two — they'll appear here automatically once ready.
              </p>
            </div>
          </div>
        <% :failed -> %>
          <div class="rounded-3xl border border-red-100 bg-red-50 p-6">
            <div class="flex items-center gap-4">
              <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-red-600 shadow-sm">
                <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
              </span>
              <div>
                <p class="font-semibold text-ink">
                  We couldn't generate flashcards for this scope.
                </p>
                <p class="mt-0.5 text-sm text-body">
                  This can happen when the module has no practice questions yet and no
                  readable lessons to fall back on.
                </p>
              </div>
            </div>
            <button
              type="button"
              phx-click="retry-flashcard-generation"
              class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" /> Try again
            </button>
          </div>
        <% :ready -> %>
          <.flashcard_review
            set={@flashcard_set}
            cards={@flashcard_cards}
            index={@flashcard_index}
            flipped?={@flashcard_flipped?}
          />
      <% end %>
    </div>
    """
  end

  # Nothing is generated until the learner asks for it, so a set that has
  # never been generated shows the scope they're about to spend a generation
  # on — and lets them re-point it at the whole module or a single lesson
  # right here, rather than walking back through the pickers.
  attr :module, :map, required: true
  attr :scope, :map, required: true

  defp flashcard_setup(assigns) do
    ~H"""
    <div>
      <h2 class="text-2xl font-semibold tracking-tight text-ink">Build your flashcards</h2>
      <p class="mt-2 text-body">
        Pick what these cards should cover, then generate them. We'll read the lessons and
        resources in your choice and draft a deck with AI.
      </p>

      <div class="mt-6 grid gap-3 sm:grid-cols-2">
        <button
          type="button"
          phx-click="select-scope"
          phx-value-scope="module"
          class={[
            "flex items-center justify-between gap-3 rounded-2xl border p-4 text-left text-sm transition",
            if(module_scope?(@scope),
              do: "border-primary bg-mint/50 text-ink",
              else:
                "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
            )
          ]}
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">Whole module</span>
            <span class="mt-0.5 block text-xs text-muted">
              Covers all {length(@module.lectures)} lectures
            </span>
          </span>
          <.icon
            :if={module_scope?(@scope)}
            name="hero-check-circle"
            class="h-5 w-5 shrink-0 text-primary"
          />
        </button>
        <button
          :for={lecture <- @module.lectures}
          type="button"
          phx-click="select-scope"
          phx-value-scope="lecture"
          phx-value-lecture_id={lecture.id}
          class={[
            "flex items-center justify-between gap-3 rounded-2xl border p-4 text-left text-sm transition",
            if(lecture_scope?(@scope, lecture),
              do: "border-primary bg-mint/50 text-ink",
              else:
                "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40 hover:text-ink"
            )
          ]}
        >
          <span class="min-w-0">
            <span class="block truncate font-medium text-ink">{lecture.title}</span>
            <span class="mt-0.5 block text-xs text-muted">Just this lesson</span>
          </span>
          <.icon
            :if={lecture_scope?(@scope, lecture)}
            name="hero-check-circle"
            class="h-5 w-5 shrink-0 text-primary"
          />
        </button>
      </div>

      <button
        type="button"
        phx-click="generate-flashcards"
        class="mt-6 inline-flex items-center gap-1.5 rounded-full bg-ink px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-primary"
      >
        <.icon name="hero-sparkles" class="h-4 w-4" />
        Generate flashcards for {flashcard_scope_label(@scope)}
      </button>
    </div>
    """
  end

  defp module_scope?(%CourseModule{}), do: true
  defp module_scope?(_scope), do: false

  defp lecture_scope?(%Lecture{id: id}, %{id: id}), do: true
  defp lecture_scope?(_scope, _lecture), do: false

  defp flashcard_scope_label(%CourseModule{}), do: "the whole module"
  defp flashcard_scope_label(%Lecture{title: title}), do: title

  attr :set, :map, required: true
  attr :cards, :list, required: true
  attr :index, :integer, required: true
  attr :flipped?, :boolean, required: true

  defp flashcard_review(assigns) do
    counts = flashcard_status_counts(assigns.cards)

    assigns =
      assign(assigns,
        total: length(assigns.cards),
        counts: counts,
        retained_count: counts.known + counts.mastered
      )

    ~H"""
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div class="min-w-0">
        <h2 class="text-2xl font-semibold tracking-tight text-ink">Flashcards</h2>
        <p class="mt-1 text-sm font-medium text-body">{flashcard_source_label(@set.source)}</p>
      </div>
      <div class="flex shrink-0 items-center gap-3">
        <span class="rounded-full border-2 border-primary px-4 py-1.5 text-sm font-bold text-primary">
          {@total} cards
        </span>
        <button
          type="button"
          phx-click="regenerate-flashcards"
          class="inline-flex items-center gap-1.5 rounded-full border-2 border-primary px-4 py-1.5 text-sm font-semibold text-primary transition hover:bg-primary hover:text-white"
        >
          <.icon name="hero-sparkles" class="h-4 w-4" /> Generate a new deck
        </button>
      </div>
    </div>

    <%= if @cards == [] do %>
      <div class="mt-6 grid min-h-[320px] place-items-center text-center text-muted">
        There aren't any flashcards here yet.
      </div>
    <% else %>
      <div class="mt-6 grid grid-cols-2 gap-3 rounded-2xl border-2 border-ink bg-white p-4 text-center sm:grid-cols-4">
        <div :for={{label, count} <- flashcard_status_tiles(@counts)}>
          <p class="text-2xl font-bold text-ink">{count}</p>
          <p class="mt-0.5 text-xs font-semibold text-body">{label}</p>
        </div>
      </div>

      <%= if @index >= @total do %>
        <div class="grid min-h-[320px] place-items-center text-center">
          <div>
            <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-mint text-primary">
              <.icon name="hero-check-circle" class="h-8 w-8" />
            </span>
            <h3 class="mt-4 text-2xl font-bold text-ink">Deck complete!</h3>
            <p class="mt-2 text-body">
              You've got {@retained_count} of {@total} cards down.
            </p>
            <div class="mt-6 flex flex-wrap justify-center gap-3">
              <button
                :if={@retained_count < @total}
                type="button"
                phx-click="review-unknown-flashcards"
                class="rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
              >
                Review the rest
              </button>
              <button
                type="button"
                phx-click="restart-flashcard-deck"
                class="rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-mint"
              >
                Restart deck
              </button>
            </div>
          </div>
        </div>
      <% else %>
        <% entry = Enum.at(@cards, @index) %>
        <div class="mt-5 h-2 overflow-hidden rounded-full bg-orange-100">
          <div
            class="h-full rounded-full bg-primary transition-all duration-300"
            style={"width: #{round((@index + 1) / @total * 100)}%"}
          >
          </div>
        </div>

        <button
          type="button"
          phx-click="flip-flashcard"
          class="mt-6 block h-80 w-full [perspective:1200px] sm:h-96"
        >
          <div class={[
            "relative h-full w-full rounded-2xl transition-transform duration-500 [transform-style:preserve-3d]",
            @flipped? && "[transform:rotateY(180deg)]"
          ]}>
            <div class="absolute inset-0 flex flex-col items-center justify-center rounded-3xl border-2 border-ink bg-primary p-8 text-center shadow-sm [backface-visibility:hidden]">
              <span class="text-xs font-bold uppercase tracking-widest text-white">
                Question
              </span>
              <p class="mt-5 max-w-4xl text-2xl font-semibold leading-snug text-white sm:text-3xl">
                {entry.flashcard.front}
              </p>
              <span class="mt-6 inline-flex items-center gap-2 text-sm font-semibold text-white">
                <.icon name="hero-arrow-path-rounded-square" class="h-5 w-5" />
                Tap to reveal the answer
              </span>
            </div>
            <div class="absolute inset-0 flex flex-col items-center justify-center rounded-3xl border-[3px] border-orange-500 bg-soft p-8 text-center shadow-sm ring-1 ring-ink [backface-visibility:hidden] [transform:rotateY(180deg)]">
              <span class="text-xs font-bold uppercase tracking-widest text-ink">Answer</span>
              <p class="mt-5 max-w-4xl text-xl font-semibold leading-relaxed text-ink sm:text-2xl">
                {entry.flashcard.back}
              </p>
              <span class="mt-6 inline-flex items-center gap-2 text-sm font-semibold text-body">
                <.icon name="hero-arrow-path-rounded-square" class="h-5 w-5" />
                Tap to see the question
              </span>
            </div>
          </div>
        </button>

        <div class="mt-6 grid gap-3 sm:grid-cols-3">
          <button
            :for={{rating, label, hint} <- flashcard_ratings()}
            type="button"
            phx-click="rate-flashcard"
            phx-value-rating={rating}
            class="rounded-2xl border-2 border-ink bg-ink px-5 py-4 text-left text-white transition hover:border-primary hover:bg-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            <span class="block text-sm font-semibold">{label}</span>
            <span class="mt-0.5 block text-xs text-white/80">
              {hint}
            </span>
          </button>
        </div>

        <div class="mt-4 flex items-center justify-between gap-3">
          <button
            type="button"
            phx-click="flashcard-prev"
            disabled={@index == 0}
            class="inline-flex items-center gap-1.5 rounded-xl border-2 border-ink px-5 py-3 text-sm font-semibold text-ink transition hover:bg-soft disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Previous
          </button>
          <span class="text-sm font-bold text-body">Card {@index + 1} of {@total}</span>
          <button
            type="button"
            phx-click="flashcard-next"
            class="inline-flex items-center gap-1.5 rounded-xl border-2 border-ink bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
          >
            Next <.icon name="hero-arrow-right" class="h-4 w-4" />
          </button>
        </div>
      <% end %>
    <% end %>
    """
  end

  # "Again"/"Got it"/"Easy" map onto the three `FlashcardProgress` ratings;
  # an unrated card counts as Reviewing rather than as its own status, so the
  # four tiles always sum to the deck size.
  defp flashcard_ratings do
    [
      {"review_again", "Again", "Still learning"},
      {"known", "Got it", "Review later"},
      {"mastered", "Easy", "Mark mastered"}
    ]
  end

  defp flashcard_status_tiles(counts) do
    [
      {"Learning", counts.learning},
      {"Reviewing", counts.reviewing},
      {"Known", counts.known},
      {"Mastered", counts.mastered}
    ]
  end

  defp flashcard_status_counts(cards) do
    Enum.reduce(cards, %{learning: 0, reviewing: 0, known: 0, mastered: 0}, fn card, counts ->
      Map.update!(counts, flashcard_status_bucket(card.progress), &(&1 + 1))
    end)
  end

  defp flashcard_status_bucket(%{status: :review_again}), do: :learning
  defp flashcard_status_bucket(%{status: :known}), do: :known
  defp flashcard_status_bucket(%{status: :mastered}), do: :mastered
  defp flashcard_status_bucket(_progress), do: :reviewing

  defp flashcard_source_label(:practice_questions),
    do: "Drawn from this module's practice questions."

  defp flashcard_source_label(:lesson_text), do: "Drawn from your lessons and resources."
  defp flashcard_source_label(_source), do: "Recall key ideas one card at a time."

  attr :practice_set, :map, required: true
  attr :practice_set_questions, :list, required: true
  attr :practice_answers, :map, required: true
  attr :practice_index, :integer, required: true

  def practice_set_panel(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <%= case @practice_set.status do %>
        <% status when status in [:pending, :processing] -> %>
          <div class="flex items-center gap-4 rounded-3xl border border-primary/20 bg-mint/40 p-6">
            <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-primary shadow-sm">
              <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin" />
            </span>
            <div>
              <p class="font-semibold text-ink">Generating extra practice questions…</p>
              <p class="mt-0.5 text-sm text-body">
                We're reading your lessons and drafting self-check questions with AI. This
                usually takes a minute or two — they'll appear here automatically once
                ready.
              </p>
            </div>
          </div>
        <% :failed -> %>
          <div class="rounded-3xl border border-red-100 bg-red-50 p-6">
            <div class="flex items-center gap-4">
              <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-red-600 shadow-sm">
                <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
              </span>
              <div>
                <p class="font-semibold text-ink">
                  We couldn't generate practice questions for this scope.
                </p>
                <p class="mt-0.5 text-sm text-body">
                  This can happen if there aren't any readable lessons yet.
                </p>
              </div>
            </div>
            <button
              type="button"
              phx-click="retry-practice-generation"
              class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
            >
              <.icon name="hero-arrow-path" class="h-4 w-4" /> Try again
            </button>
          </div>
        <% :ready -> %>
          <.practice_review
            questions={@practice_set_questions}
            answers={@practice_answers}
            index={@practice_index}
          />
      <% end %>
    </div>
    """
  end

  attr :questions, :list, required: true
  attr :answers, :map, required: true
  attr :index, :integer, required: true

  defp practice_review(assigns) do
    total = length(assigns.questions)

    correct_count =
      Enum.count(assigns.questions, fn question ->
        case Map.get(assigns.answers, question.id) do
          nil -> false
          option_id -> Assessments.practice_answer_correct?(question, option_id)
        end
      end)

    assigns = assign(assigns, total: total, correct_count: correct_count)

    ~H"""
    <%= if @questions == [] do %>
      <div class="grid min-h-[320px] place-items-center text-center text-muted">
        There aren't any practice questions here yet.
      </div>
    <% else %>
      <%= if @index >= @total do %>
        <div class="grid min-h-[320px] place-items-center text-center">
          <div>
            <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-mint text-primary">
              <.icon name="hero-check-circle" class="h-8 w-8" />
            </span>
            <h3 class="mt-4 text-2xl font-bold text-ink">Nice work!</h3>
            <p class="mt-2 text-body">You got {@correct_count} of {@total} correct.</p>
            <div class="mt-6 flex justify-center">
              <button
                type="button"
                phx-click="restart-practice-set"
                class="rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
              >
                Practice again
              </button>
            </div>
          </div>
        </div>
      <% else %>
        <% question = Enum.at(@questions, @index) %>
        <% answer = Map.get(@answers, question.id) %>
        <div class="flex items-center justify-between text-xs text-muted">
          <span>Question {@index + 1} of {@total}</span>
          <span>{@correct_count} correct so far</span>
        </div>
        <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-mint">
          <div
            class="h-full rounded-full bg-primary transition-all duration-300"
            style={"width: #{round((@index + 1) / @total * 100)}%"}
          >
          </div>
        </div>

        <div class="mt-6 rounded-2xl border border-black/5 p-6">
          <h3 class="text-lg font-medium leading-snug text-ink">{question.prompt}</h3>

          <div class="mt-4 space-y-2.5">
            <button
              :for={option <- question.practice_set_question_options}
              type="button"
              phx-click="select-practice-option"
              phx-value-question-id={question.id}
              phx-value-option-id={option.id}
              disabled={!!answer}
              class={[
                "flex w-full items-center gap-3 rounded-xl border p-3.5 text-left text-sm transition",
                practice_option_class(answer, option)
              ]}
            >
              <span class="flex-1">{option.label}</span>
              <.icon
                :if={answer && option.correct}
                name="hero-check-circle"
                class="h-5 w-5 shrink-0 text-primary"
              />
              <.icon
                :if={answer && !option.correct && to_string(option.id) == to_string(answer)}
                name="hero-x-circle"
                class="h-5 w-5 shrink-0 text-red-600"
              />
            </button>
          </div>

          <div
            :if={answer}
            class={[
              "mt-4 rounded-xl p-4 text-sm",
              if(Assessments.practice_answer_correct?(question, answer),
                do: "bg-mint text-ink",
                else: "bg-red-50 text-ink"
              )
            ]}
          >
            <p class="font-semibold">
              {if Assessments.practice_answer_correct?(question, answer),
                do: "Correct!",
                else: "Not quite."}
            </p>
            <p :if={question.explanation} class="mt-1 text-body">{question.explanation}</p>
          </div>
        </div>

        <div class="mt-6 flex items-center justify-between border-t border-black/5 pt-6">
          <button
            type="button"
            phx-click="practice-prev"
            disabled={@index == 0}
            class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-mint disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
          </button>
          <button
            type="button"
            phx-click="practice-next"
            disabled={!answer}
            class="inline-flex items-center gap-1.5 rounded-full bg-primary px-6 py-2.5 text-sm font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
          >
            Next <.icon name="hero-arrow-right" class="h-4 w-4" />
          </button>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp practice_option_class(nil, _option),
    do: "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40 cursor-pointer"

  defp practice_option_class(answer, option) do
    cond do
      option.correct -> "border-primary bg-mint text-ink font-medium"
      to_string(option.id) == to_string(answer) -> "border-red-300 bg-red-50 text-ink"
      true -> "border-black/10 text-muted opacity-60"
    end
  end

  ## Smart Test
  #
  # One panel with five faces, driven by the test's own state rather than by a
  # separate wizard step in the LiveView: settings (no test yet, or the
  # learner came back to build another), generating, failed, ready-to-start,
  # taking, and results. `@view` only distinguishes "the learner is looking at
  # the settings form" from "the learner is looking at their test", so
  # reloading mid-test lands them back in the test.

  # Rough per-question pacing used only for the "About N min" hints next to
  # the counts — a recall question reads and answers far faster than a written
  # one, so the two kinds are estimated separately.
  @seconds_per_multiple_choice 40
  @seconds_per_short_answer 120

  attr :smart_test, :any, default: nil
  attr :settings, :map, required: true
  attr :scope_label, :string, required: true
  attr :view, :atom, required: true
  attr :remaining_seconds, :any, default: nil
  attr :saved_tests, :list, default: []

  def smart_test_panel(assigns) do
    ~H"""
    <%= if @view == :settings or is_nil(@smart_test) do %>
      <.smart_test_settings
        settings={@settings}
        scope_label={@scope_label}
        smart_test={@smart_test}
        saved_tests={@saved_tests}
      />
    <% else %>
      <%= case @smart_test.status do %>
        <% status when status in [:pending, :processing] -> %>
          <.smart_test_shell scope_label={@scope_label} remaining_seconds={nil} smart_test={nil}>
            <div class="grid min-h-[320px] place-items-center p-8 text-center lg:p-10">
              <div>
                <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                  <.icon name="hero-arrow-path" class="h-7 w-7 animate-spin" />
                </span>
                <h3 class="mt-4 text-xl font-semibold text-ink">Building your Smart Test…</h3>
                <p class="mx-auto mt-2 max-w-md text-sm text-body">
                  We're reading this lesson and writing {@smart_test.multiple_choice_count} multiple choice and {@smart_test.short_answer_count} short answer questions at difficulty {@smart_test.difficulty}. This usually takes a minute — it'll appear here
                  automatically.
                </p>
              </div>
            </div>
          </.smart_test_shell>
        <% :failed -> %>
          <.smart_test_shell scope_label={@scope_label} remaining_seconds={nil} smart_test={nil}>
            <div class="p-8 lg:p-10">
              <div class="rounded-3xl border border-red-100 bg-red-50 p-6">
                <div class="flex items-center gap-4">
                  <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-red-600 shadow-sm">
                    <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
                  </span>
                  <div>
                    <p class="font-semibold text-ink">We couldn't build this Smart Test.</p>
                    <p class="mt-0.5 text-sm text-body">
                      This can happen if there aren't any readable lessons or resources here yet.
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="retry-smart-test-generation"
                  class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" /> Try again
                </button>
              </div>
            </div>
          </.smart_test_shell>
        <% :ready -> %>
          <%= cond do %>
            <% @smart_test.completed_at -> %>
              <.smart_test_results smart_test={@smart_test} scope_label={@scope_label} />
            <% is_nil(@smart_test.started_at) or @smart_test.paused_at -> %>
              <.smart_test_shell
                scope_label={@scope_label}
                remaining_seconds={@remaining_seconds}
                smart_test={nil}
              >
                <.smart_test_launchpad
                  smart_test={@smart_test}
                  remaining_seconds={@remaining_seconds}
                />
              </.smart_test_shell>
            <% true -> %>
              <.smart_test_shell
                scope_label={@scope_label}
                remaining_seconds={@remaining_seconds}
                smart_test={@smart_test}
              >
                <.smart_test_questions smart_test={@smart_test} scope_label={@scope_label} />
              </.smart_test_shell>
          <% end %>
      <% end %>
    <% end %>
    """
  end

  attr :settings, :map, required: true
  attr :scope_label, :string, required: true
  attr :smart_test, :any, default: nil
  attr :saved_tests, :list, default: []

  defp smart_test_settings(assigns) do
    total = assigns.settings.multiple_choice_count + assigns.settings.short_answer_count
    assigns = assign(assigns, :total, total)

    ~H"""
    <div>
      <div class="flex flex-wrap items-start justify-between gap-4 p-8 pb-6 lg:p-10 lg:pb-6">
        <div>
          <h2 class="text-3xl font-semibold tracking-tight text-primary">Smart Test</h2>
          <p class="mt-2 text-sm text-body">{@scope_label}</p>
        </div>
        <button
          type="button"
          phx-click="select-mode"
          phx-value-mode="practice"
          class="inline-flex items-center gap-2 rounded-full border border-black/10 px-4 py-2.5 text-sm font-semibold text-ink transition hover:border-primary/40 hover:bg-mint/40"
        >
          <.icon name="hero-sparkles" class="h-4 w-4 text-primary" /> Adaptive practice
        </button>
      </div>

      <form phx-change="change-smart-test-settings" phx-submit="create-smart-test">
        <div class="grid border-y border-black/5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)]">
          <div class="border-b border-black/5 p-8 lg:border-b-0 lg:border-r lg:p-10">
            <h3 class="text-xl font-semibold text-primary">Time</h3>
            <p class="mt-1.5 text-sm text-body">Choose a focused test duration.</p>

            <div class="mt-6 flex items-center gap-4">
              <button
                type="button"
                phx-click="step-smart-test-duration"
                phx-value-by="-5"
                class="grid h-11 w-11 place-items-center rounded-full border border-black/10 text-ink transition hover:border-primary/40 hover:bg-mint/40"
                aria-label="Decrease duration"
              >
                <.icon name="hero-minus" class="h-4 w-4" />
              </button>
              <span class="min-w-[5rem] text-center text-2xl font-bold text-primary tabular-nums">
                {@settings.duration_minutes} min
              </span>
              <button
                type="button"
                phx-click="step-smart-test-duration"
                phx-value-by="5"
                class="grid h-11 w-11 place-items-center rounded-full border border-black/10 text-ink transition hover:border-primary/40 hover:bg-mint/40"
                aria-label="Increase duration"
              >
                <.icon name="hero-plus" class="h-4 w-4" />
              </button>
              <input
                type="hidden"
                name="settings[duration_minutes]"
                value={@settings.duration_minutes}
              />
            </div>

            <label class="mt-5 inline-flex cursor-pointer items-center gap-2.5 text-sm font-semibold text-ink">
              <input type="hidden" name="settings[enforce_time_limit]" value="false" />
              <input
                type="checkbox"
                name="settings[enforce_time_limit]"
                value="true"
                checked={@settings.enforce_time_limit}
                class="h-4 w-4 rounded border-black/20 text-primary focus:ring-primary"
              /> Enforce time limit
            </label>
          </div>

          <div class="p-8 lg:p-10">
            <h3 class="text-xl font-semibold text-primary">Questions</h3>
            <p class="mt-1.5 text-sm text-body">Balance recall and written responses.</p>

            <div class="mt-6 grid gap-6 border-b border-black/5 pb-5 sm:grid-cols-2">
              <div>
                <div class="flex items-center justify-between gap-3">
                  <label for="smart-test-multiple-choice" class="text-sm font-semibold text-ink">
                    Multiple choice
                  </label>
                  <input
                    type="number"
                    id="smart-test-multiple-choice"
                    name="settings[multiple_choice_count]"
                    value={@settings.multiple_choice_count}
                    min="0"
                    max={Assessments.SmartTest.max_multiple_choice()}
                    class="w-16 rounded-xl border-black/10 py-2 text-center text-sm font-semibold text-ink focus:border-primary focus:ring-primary"
                  />
                </div>
                <p class="mt-2 text-xs text-muted">
                  About {estimated_minutes(@settings.multiple_choice_count, :multiple_choice)} min
                </p>
              </div>
              <div>
                <div class="flex items-center justify-between gap-3">
                  <label for="smart-test-short-answer" class="text-sm font-semibold text-ink">
                    Short answer
                  </label>
                  <input
                    type="number"
                    id="smart-test-short-answer"
                    name="settings[short_answer_count]"
                    value={@settings.short_answer_count}
                    min="0"
                    max={Assessments.SmartTest.max_short_answer()}
                    class="w-16 rounded-xl border-black/10 py-2 text-center text-sm font-semibold text-ink focus:border-primary focus:ring-primary"
                  />
                </div>
                <p class="mt-2 text-xs text-muted">
                  About {estimated_minutes(@settings.short_answer_count, :short_answer)} min
                </p>
              </div>
            </div>

            <div class="mt-5">
              <label for="smart-test-difficulty" class="text-sm font-semibold text-ink">
                Difficulty
              </label>
              <input
                type="range"
                id="smart-test-difficulty"
                name="settings[difficulty]"
                min="1"
                max="5"
                step="1"
                value={@settings.difficulty}
                class="mt-3 h-1.5 w-full cursor-pointer appearance-none rounded-full bg-black/10 accent-primary"
              />
              <div class="mt-2 flex items-center justify-between text-xs font-semibold text-ink">
                <span>Easy</span>
                <span>{@settings.difficulty} of 5</span>
                <span>Hard</span>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 p-8 lg:px-10">
          <div>
            <p class="text-sm font-semibold text-primary">
              {@total} {if @total == 1, do: "question", else: "questions"}
            </p>
            <p class="mt-0.5 text-sm text-muted">
              {if @settings.enforce_time_limit,
                do: "#{@settings.duration_minutes} minute limit",
                else: "No time limit"}
            </p>
          </div>
          <button
            type="submit"
            disabled={@total == 0}
            class="inline-flex items-center gap-2 rounded-2xl bg-primary px-6 py-3.5 text-base font-semibold text-white transition hover:bg-ink disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-sparkles" class="h-5 w-5" /> Create test
          </button>
        </div>
      </form>

      <div :if={@smart_test} class="p-8 lg:p-10">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 class="text-xl font-semibold text-primary">Saved test</h3>
            <p class="mt-1.5 text-sm text-body">Continue your latest test with the same settings.</p>
          </div>
          <span class="rounded-full border border-black/10 px-4 py-2 text-xs font-semibold text-ink">
            {smart_test_state_label(@smart_test)}
          </span>
        </div>

        <div class="mt-6 grid items-center gap-4 border-t border-black/5 pt-6 lg:grid-cols-[minmax(0,1.4fr)_repeat(3,minmax(0,0.6fr))_auto]">
          <div class="min-w-0">
            <p class="font-semibold text-ink">Smart Test {length(@saved_tests)}</p>
            <p class="mt-0.5 text-sm text-muted">
              {@smart_test.multiple_choice_count} multiple choice · {@smart_test.short_answer_count} short answer
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-muted">Difficulty</p>
            <p class="mt-1 text-sm font-semibold text-primary">{@smart_test.difficulty} of 5</p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-muted">Duration</p>
            <p class="mt-1 text-sm font-semibold text-primary">
              {if @smart_test.enforce_time_limit,
                do: "#{@smart_test.duration_minutes} min",
                else: "Untimed"}
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-muted">Score</p>
            <p class="mt-1 text-sm font-semibold text-primary">
              {if @smart_test.score_percent, do: "#{@smart_test.score_percent}%", else: "—"}
            </p>
          </div>
          <button
            type="button"
            phx-click="open-smart-test"
            class="inline-flex items-center gap-2 rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
          >
            {smart_test_open_label(@smart_test)} <.icon name="hero-chevron-right" class="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :scope_label, :string, required: true
  attr :remaining_seconds, :any, default: nil
  attr :smart_test, :any, default: nil
  slot :inner_block, required: true

  # The shared test-taking chrome: back to settings on the left, the clock in
  # the middle, and — only once the learner is actually working through
  # questions (`@smart_test` set) — pause and Finish test.
  defp smart_test_shell(assigns) do
    ~H"""
    <div>
      <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 p-6 lg:px-10">
        <button
          type="button"
          phx-click="open-smart-test-settings"
          class="inline-flex items-center gap-2 rounded-2xl border border-black/10 px-5 py-3 text-sm font-semibold text-ink transition hover:border-primary/40 hover:bg-mint/40"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4" /> Test settings
        </button>

        <div :if={@remaining_seconds} class="flex items-center gap-3">
          <.icon name="hero-clock" class="h-5 w-5 text-primary" />
          <span
            id="smart-test-countdown"
            phx-hook="QuizCountdown"
            phx-update="ignore"
            data-deadline={countdown_deadline(@remaining_seconds)}
            data-total-seconds={@remaining_seconds}
            class="text-xl font-bold tabular-nums text-primary"
          >
            {format_seconds(@remaining_seconds)}
          </span>
          <button
            :if={@smart_test}
            type="button"
            phx-click="pause-smart-test"
            class="grid h-8 w-8 place-items-center rounded-full bg-ink text-white transition hover:bg-primary"
            aria-label="Pause test"
          >
            <.icon name="hero-pause" class="h-4 w-4" />
          </button>
        </div>

        <button
          :if={@smart_test}
          id="finish-smart-test-top"
          type="button"
          phx-click="finish-smart-test"
          class="rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
        >
          Finish test
        </button>
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :smart_test, :map, required: true
  attr :remaining_seconds, :any, default: nil

  defp smart_test_launchpad(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <div class="grid min-h-[420px] place-items-center rounded-3xl bg-black/[0.03] p-8 text-center">
        <div>
          <span class="mx-auto grid h-20 w-20 place-items-center rounded-2xl bg-primary text-white">
            <.icon name="hero-play" class="h-9 w-9" />
          </span>
          <h3 class="mt-6 text-2xl font-semibold text-primary">
            {if @smart_test.paused_at, do: "Test paused", else: "Your Smart Test is ready"}
          </h3>
          <p class="mt-3 text-body">
            {@smart_test.multiple_choice_count} multiple choice · {@smart_test.short_answer_count} short answer · Difficulty {@smart_test.difficulty}
          </p>
          <p :if={@remaining_seconds} class="mt-1 text-sm text-muted">
            {format_seconds(@remaining_seconds)} on the clock
          </p>
          <button
            type="button"
            phx-click="start-smart-test"
            class="mt-7 inline-flex items-center gap-2 rounded-2xl bg-primary px-7 py-4 text-base font-semibold text-white transition hover:bg-ink"
          >
            {if @smart_test.started_at, do: "Resume your test", else: "Start your test"}
            <.icon name="hero-chevron-right" class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :smart_test, :map, required: true
  attr :scope_label, :string, required: true

  # Every question on one page (rather than one at a time as the untimed
  # panels do): a timed test is about budgeting the clock across questions,
  # which needs them all visible and skippable.
  defp smart_test_questions(assigns) do
    assigns = assign(assigns, :questions, assigns.smart_test.smart_test_questions)

    ~H"""
    <div>
      <div class="border-b border-black/5 p-8 lg:px-10">
        <h2 class="text-3xl font-semibold tracking-tight text-primary">{@scope_label}</h2>
        <p class="mt-2 text-sm text-body">Complete every question, then check your score.</p>
      </div>

      <div class="space-y-5 p-6 lg:p-8">
        <div
          :for={{question, index} <- Enum.with_index(@questions, 1)}
          class="overflow-hidden rounded-3xl border border-black/10"
        >
          <div class="p-6">
            <p class="text-xs font-semibold uppercase tracking-wider text-muted">
              {smart_test_kind_label(question.kind)} · {index} of {length(@questions)}
            </p>
            <h3 class="mt-2 text-lg font-semibold leading-snug text-primary">{question.prompt}</h3>
          </div>

          <div
            :if={question.kind == :multiple_choice}
            class="grid gap-4 border-t border-black/5 p-6 sm:grid-cols-2"
          >
            <button
              :for={{option, option_index} <- Enum.with_index(question.smart_test_question_options)}
              type="button"
              phx-click="answer-smart-test-choice"
              phx-value-question-id={question.id}
              phx-value-option-id={option.id}
              class={[
                "flex items-start gap-4 rounded-2xl border p-4 text-left text-sm transition",
                if(question.response_option_id == option.id,
                  do: "border-primary bg-mint text-ink font-medium",
                  else:
                    "border-black/10 bg-black/[0.03] text-body hover:border-primary/40 hover:bg-mint/40"
                )
              ]}
            >
              <span class={[
                "grid h-7 w-7 shrink-0 place-items-center rounded-full text-xs font-bold",
                if(question.response_option_id == option.id,
                  do: "bg-primary text-white",
                  else: "bg-ink text-white"
                )
              ]}>
                {option_letter(option_index)}
              </span>
              <span class="flex-1">{option.label}</span>
            </button>
          </div>

          <div :if={question.kind == :short_answer} class="border-t border-black/5 p-6">
            <form phx-change="answer-smart-test-text" phx-submit="answer-smart-test-text">
              <input type="hidden" name="question_id" value={question.id} />
              <textarea
                name="response"
                rows="4"
                phx-debounce="600"
                placeholder="Write your answer in two or three sentences…"
                class="w-full rounded-2xl border-black/10 text-sm text-ink focus:border-primary focus:ring-primary"
              >{question.response_text}</textarea>
            </form>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center justify-between gap-4 border-t border-black/5 p-6 lg:px-10">
        <p class="text-sm text-muted">
          {smart_test_answered_count(@questions)} of {length(@questions)} answered
        </p>
        <button
          id="finish-smart-test-bottom"
          type="button"
          phx-click="finish-smart-test"
          class="rounded-2xl bg-primary px-6 py-3.5 text-base font-semibold text-white transition hover:bg-ink"
        >
          Finish test
        </button>
      </div>
    </div>
    """
  end

  attr :smart_test, :map, required: true
  attr :scope_label, :string, required: true

  defp smart_test_results(assigns) do
    questions = assigns.smart_test.smart_test_questions

    assigns =
      assign(assigns,
        questions: questions,
        correct_count: Enum.count(questions, &Assessments.smart_test_question_correct?/1)
      )

    ~H"""
    <div>
      <div class={[
        "p-8 text-center lg:p-10",
        if(@smart_test.score_percent >= 70, do: "bg-mint", else: "bg-red-50")
      ]}>
        <div class={[
          "mx-auto grid h-16 w-16 place-items-center rounded-full bg-white",
          if(@smart_test.score_percent >= 70, do: "text-primary", else: "text-red-600")
        ]}>
          <.icon
            name={if @smart_test.score_percent >= 70, do: "hero-check-circle", else: "hero-x-circle"}
            class="h-8 w-8"
          />
        </div>
        <h3 class="mt-4 text-2xl font-bold text-ink">
          {if @smart_test.time_expired, do: "Time's up!", else: "Test complete"}
        </h3>
        <p class={[
          "mt-2 text-4xl font-extrabold",
          if(@smart_test.score_percent >= 70, do: "text-primary", else: "text-red-600")
        ]}>
          {@smart_test.score_percent}%
        </p>
        <p class="mt-2 text-sm text-body">
          {@correct_count} of {length(@questions)} questions right · {@scope_label}
        </p>
        <div class="mt-6 flex flex-wrap justify-center gap-3">
          <button
            type="button"
            phx-click="retake-smart-test"
            class="rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
          >
            Retake this test
          </button>
          <button
            type="button"
            phx-click="open-smart-test-settings"
            class="rounded-2xl border border-black/10 bg-white px-5 py-3 text-sm font-semibold text-ink transition hover:bg-ink hover:text-white"
          >
            Build a new test
          </button>
        </div>
      </div>

      <div class="space-y-5 p-6 lg:p-8">
        <div
          :for={{question, index} <- Enum.with_index(@questions, 1)}
          class="overflow-hidden rounded-3xl border border-black/10"
        >
          <div class="flex flex-wrap items-start justify-between gap-3 p-6">
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase tracking-wider text-muted">
                {smart_test_kind_label(question.kind)} · {index} of {length(@questions)}
              </p>
              <h3 class="mt-2 text-lg font-semibold leading-snug text-primary">{question.prompt}</h3>
            </div>
            <span class={[
              "shrink-0 rounded-full px-3 py-1 text-xs font-semibold",
              smart_test_verdict_class(question)
            ]}>
              {smart_test_verdict_label(question)}
            </span>
          </div>

          <div
            :if={question.kind == :multiple_choice}
            class="grid gap-3 border-t border-black/5 p-6 sm:grid-cols-2"
          >
            <div
              :for={option <- question.smart_test_question_options}
              class={[
                "flex items-start gap-3 rounded-2xl border p-4 text-sm",
                smart_test_review_option_class(question, option)
              ]}
            >
              <span class="flex-1">{option.label}</span>
              <.icon
                :if={option.correct}
                name="hero-check-circle"
                class="h-5 w-5 shrink-0 text-primary"
              />
              <.icon
                :if={!option.correct && question.response_option_id == option.id}
                name="hero-x-circle"
                class="h-5 w-5 shrink-0 text-red-600"
              />
            </div>
          </div>

          <div :if={question.kind == :short_answer} class="space-y-4 border-t border-black/5 p-6">
            <div>
              <p class="text-xs font-semibold uppercase tracking-wider text-muted">Your answer</p>
              <p class="mt-1.5 whitespace-pre-line text-sm text-ink">
                {if String.trim(question.response_text || "") == "",
                  do: "You didn't answer this one.",
                  else: question.response_text}
              </p>
            </div>
            <div class="rounded-2xl bg-black/[0.03] p-4">
              <p class="text-xs font-semibold uppercase tracking-wider text-muted">Model answer</p>
              <p class="mt-1.5 whitespace-pre-line text-sm text-ink">{question.expected_answer}</p>
            </div>
          </div>

          <p
            :if={question.explanation}
            class="border-t border-black/5 bg-mint/30 p-6 text-sm text-body"
          >
            {question.explanation}
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Default settings for a brand-new Smart Test — the same shape the settings
  form reads and writes, so `StudyHubLive` never hand-rolls it.
  """
  def default_smart_test_settings do
    %{
      duration_minutes: 10,
      enforce_time_limit: true,
      multiple_choice_count: 6,
      short_answer_count: 2,
      difficulty: 3
    }
  end

  @doc "Reads a saved test's settings back into the form, so \"Build a new test\" starts from the last one."
  def smart_test_settings_from(%Assessments.SmartTest{} = smart_test) do
    %{
      duration_minutes: smart_test.duration_minutes,
      enforce_time_limit: smart_test.enforce_time_limit,
      multiple_choice_count: smart_test.multiple_choice_count,
      short_answer_count: smart_test.short_answer_count,
      difficulty: smart_test.difficulty
    }
  end

  def smart_test_settings_from(nil), do: default_smart_test_settings()

  defp estimated_minutes(count, :multiple_choice),
    do: max(ceil(count * @seconds_per_multiple_choice / 60), 0)

  defp estimated_minutes(count, :short_answer),
    do: max(ceil(count * @seconds_per_short_answer / 60), 0)

  # The countdown hook works from an absolute deadline (so it stays honest
  # across a slow render), which the server derives from the persisted
  # remaining time rather than the other way around.
  defp countdown_deadline(remaining_seconds) do
    DateTime.utc_now()
    |> DateTime.add(remaining_seconds, :second)
    |> DateTime.to_iso8601()
  end

  defp option_letter(index), do: <<?A + index::utf8>>

  defp smart_test_kind_label(:multiple_choice), do: "Multiple choice"
  defp smart_test_kind_label(:short_answer), do: "Short answer"

  defp smart_test_answered_count(questions) do
    Enum.count(questions, fn question ->
      question.response_option_id != nil or String.trim(question.response_text || "") != ""
    end)
  end

  defp smart_test_state_label(%{completed_at: completed}) when not is_nil(completed),
    do: "Completed"

  defp smart_test_state_label(%{status: status}) when status in [:pending, :processing],
    do: "Building"

  defp smart_test_state_label(%{status: :failed}), do: "Failed"
  defp smart_test_state_label(%{paused_at: paused}) when not is_nil(paused), do: "Paused"
  defp smart_test_state_label(%{started_at: started}) when not is_nil(started), do: "In progress"
  defp smart_test_state_label(_smart_test), do: "Not started"

  defp smart_test_open_label(%{completed_at: completed}) when not is_nil(completed),
    do: "Review test"

  defp smart_test_open_label(%{started_at: started}) when not is_nil(started), do: "Resume test"
  defp smart_test_open_label(_smart_test), do: "Open test"

  defp smart_test_verdict_label(%{score: nil}), do: "Not graded"

  defp smart_test_verdict_label(%{kind: :short_answer, score: score}),
    do: "#{round(score * 100)}% match"

  defp smart_test_verdict_label(question) do
    if Assessments.smart_test_question_correct?(question), do: "Correct", else: "Incorrect"
  end

  defp smart_test_verdict_class(%{score: nil}), do: "bg-black/5 text-muted"

  defp smart_test_verdict_class(question) do
    if Assessments.smart_test_question_correct?(question),
      do: "bg-mint text-primary",
      else: "bg-red-50 text-red-600"
  end

  defp smart_test_review_option_class(question, option) do
    cond do
      option.correct -> "border-primary bg-mint text-ink font-medium"
      question.response_option_id == option.id -> "border-red-300 bg-red-50 text-ink"
      true -> "border-black/10 text-muted opacity-60"
    end
  end

  defp result_passed?(%{passed: passed}), do: passed
  defp result_passed?(%Assessments.QuizSubmission{passed: passed}), do: passed
  defp result_passed?(_), do: false

  defp result_score(%{score_percent: score}), do: score
  defp result_score(%Assessments.QuizSubmission{score_percent: score}), do: score
  defp result_score(_), do: 0

  defp preview_result?(%{preview?: preview?}), do: preview?
  defp preview_result?(%Assessments.QuizSubmission{}), do: false
  defp preview_result?(_), do: false

  ## Study guide
  #
  # One panel with four faces, driven by the guide's own state rather than by a
  # separate wizard step in the LiveView: the brief (no guide yet, or the
  # learner came back to write another), writing, failed, and the finished
  # document. `@view` only distinguishes "the learner is looking at the brief"
  # from "the learner is looking at their guide".
  #
  # Everything the model produced is rendered through these templates as text —
  # headings, paragraphs, bullets, terms. No model output is ever treated as
  # markup.

  attr :study_guide, :any, default: nil
  attr :settings, :map, required: true
  attr :scope_label, :string, required: true
  attr :view, :atom, required: true
  attr :saved_guides, :list, default: []

  def study_guide_panel(assigns) do
    ~H"""
    <%= if @view == :brief or is_nil(@study_guide) do %>
      <.study_guide_brief
        settings={@settings}
        scope_label={@scope_label}
        saved_guides={@saved_guides}
      />
    <% else %>
      <%= case @study_guide.status do %>
        <% status when status in [:pending, :processing] -> %>
          <.study_guide_shell study_guide={@study_guide}>
            <div class="grid min-h-[320px] place-items-center p-8 text-center lg:p-10">
              <div>
                <span class="mx-auto grid h-14 w-14 place-items-center rounded-full bg-mint text-primary">
                  <.icon name="hero-arrow-path" class="h-7 w-7 animate-spin" />
                </span>
                <h3 class="mt-4 text-xl font-semibold text-ink">Writing your study guide…</h3>
                <p class="mx-auto mt-2 max-w-md text-sm text-body">
                  We're reading this material and writing it up as {study_guide_style_phrase(
                    @study_guide.style
                  )}. This usually takes a minute — it'll appear here automatically.
                </p>
              </div>
            </div>
          </.study_guide_shell>
        <% :failed -> %>
          <.study_guide_shell study_guide={@study_guide}>
            <div class="p-8 lg:p-10">
              <div class="rounded-3xl border border-red-100 bg-red-50 p-6">
                <div class="flex items-center gap-4">
                  <span class="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-white text-red-600 shadow-sm">
                    <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
                  </span>
                  <div>
                    <p class="font-semibold text-ink">We couldn't write this study guide.</p>
                    <p class="mt-0.5 text-sm text-body">
                      This can happen if there aren't any readable lessons or resources here yet.
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  phx-click="retry-study-guide-generation"
                  class="mt-4 inline-flex items-center gap-1.5 rounded-full bg-ink px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary"
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" /> Try again
                </button>
              </div>
            </div>
          </.study_guide_shell>
        <% :ready -> %>
          <.study_guide_shell study_guide={@study_guide}>
            <.study_guide_document study_guide={@study_guide} scope_label={@scope_label} />
          </.study_guide_shell>
      <% end %>
    <% end %>
    """
  end

  attr :settings, :map, required: true
  attr :scope_label, :string, required: true
  attr :saved_guides, :list, default: []

  # The brief: the learner says how they want this material explained before a
  # single token is spent writing it. Style is the headline choice — the same
  # module as a story and as a cheat sheet are two different documents — with
  # depth, reading level and their own free-text focus narrowing it from there.
  defp study_guide_brief(assigns) do
    ~H"""
    <div>
      <div class="p-8 pb-6 lg:p-10 lg:pb-6">
        <h2 class="text-3xl font-semibold tracking-tight text-primary">Study guide</h2>
        <p class="mt-2 text-sm text-body">
          Short notes on {@scope_label}, written the way you want to read them.
        </p>
      </div>

      <form phx-change="change-study-guide-settings" phx-submit="create-study-guide">
        <div class="border-y border-black/5 p-8 lg:p-10">
          <h3 class="text-xl font-semibold text-primary">Style</h3>
          <p class="mt-1.5 text-sm text-body">How should this material be told?</p>

          <div class="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <label
              :for={{style, label, blurb, icon} <- study_guide_style_options()}
              class={[
                "flex cursor-pointer flex-col items-start gap-2 rounded-2xl border p-5 transition",
                if(@settings.style == style,
                  do: "border-primary bg-mint/50",
                  else: "border-black/10 hover:border-primary/40 hover:bg-mint/40"
                )
              ]}
            >
              <input
                type="radio"
                name="settings[style]"
                value={style}
                checked={@settings.style == style}
                class="sr-only"
              />
              <span class="grid h-10 w-10 place-items-center rounded-full bg-mint text-primary">
                <.icon name={icon} class="h-5 w-5" />
              </span>
              <span class="font-semibold text-ink">{label}</span>
              <span class="text-sm text-muted">{blurb}</span>
            </label>
          </div>
        </div>

        <div class="grid border-b border-black/5 lg:grid-cols-2">
          <div class="border-b border-black/5 p-8 lg:border-b-0 lg:border-r lg:p-10">
            <h3 class="text-xl font-semibold text-primary">How much detail?</h3>
            <p class="mt-1.5 text-sm text-body">Longer guides go into the edge cases.</p>

            <div class="mt-6 flex flex-wrap gap-2">
              <label
                :for={{depth, label, hint} <- study_guide_depth_options()}
                class={[
                  "cursor-pointer rounded-full border px-4 py-2.5 text-sm font-semibold transition",
                  if(@settings.depth == depth,
                    do: "border-primary bg-mint/50 text-ink",
                    else: "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40"
                  )
                ]}
              >
                <input
                  type="radio"
                  name="settings[depth]"
                  value={depth}
                  checked={@settings.depth == depth}
                  class="sr-only"
                />
                {label} <span class="font-normal text-muted">· {hint}</span>
              </label>
            </div>

            <h3 class="mt-8 text-xl font-semibold text-primary">Written for</h3>
            <p class="mt-1.5 text-sm text-body">How much do you already know?</p>

            <div class="mt-6 flex flex-wrap gap-2">
              <label
                :for={{level, label} <- study_guide_reading_level_options()}
                class={[
                  "cursor-pointer rounded-full border px-4 py-2.5 text-sm font-semibold transition",
                  if(@settings.reading_level == level,
                    do: "border-primary bg-mint/50 text-ink",
                    else: "border-black/10 text-body hover:border-primary/40 hover:bg-mint/40"
                  )
                ]}
              >
                <input
                  type="radio"
                  name="settings[reading_level]"
                  value={level}
                  checked={@settings.reading_level == level}
                  class="sr-only"
                />
                {label}
              </label>
            </div>
          </div>

          <div class="p-8 lg:p-10">
            <h3 class="text-xl font-semibold text-primary">Anything specific?</h3>
            <p class="mt-1.5 text-sm text-body">
              Tell us what to focus on, or leave it blank to cover everything.
            </p>

            <textarea
              id="study-guide-focus"
              name="settings[focus]"
              rows="4"
              phx-debounce="blur"
              maxlength={Assessments.StudyGuide.max_focus_chars()}
              placeholder="e.g. focus on how check digits are calculated, and use retail examples"
              class="mt-5 w-full rounded-2xl border-black/10 text-sm text-ink placeholder:text-muted focus:border-primary focus:ring-primary"
            >{@settings.focus}</textarea>

            <div class="mt-5 space-y-3">
              <label class="flex cursor-pointer items-start gap-2.5 text-sm font-semibold text-ink">
                <input type="hidden" name="settings[include_examples]" value="false" />
                <input
                  type="checkbox"
                  name="settings[include_examples]"
                  value="true"
                  checked={@settings.include_examples}
                  class="mt-0.5 h-4 w-4 rounded border-black/20 text-primary focus:ring-primary"
                />
                <span>
                  Work in examples
                  <span class="mt-0.5 block text-xs font-normal text-muted">
                    A concrete case in every section.
                  </span>
                </span>
              </label>
              <label class="flex cursor-pointer items-start gap-2.5 text-sm font-semibold text-ink">
                <input type="hidden" name="settings[include_key_terms]" value="false" />
                <input
                  type="checkbox"
                  name="settings[include_key_terms]"
                  value="true"
                  checked={@settings.include_key_terms}
                  class="mt-0.5 h-4 w-4 rounded border-black/20 text-primary focus:ring-primary"
                />
                <span>
                  Add a glossary
                  <span class="mt-0.5 block text-xs font-normal text-muted">
                    Every term the material leans on, defined.
                  </span>
                </span>
              </label>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 p-8 lg:px-10">
          <div>
            <p class="text-sm font-semibold text-primary">
              {study_guide_style_label(@settings.style)}
            </p>
            <p class="mt-0.5 text-sm text-muted">
              {study_guide_depth_label(@settings.depth)} · {study_guide_reading_level_label(
                @settings.reading_level
              )}
            </p>
          </div>
          <button
            type="submit"
            class="inline-flex items-center gap-2 rounded-2xl bg-primary px-6 py-3.5 text-base font-semibold text-white transition hover:bg-ink"
          >
            <.icon name="hero-sparkles" class="h-5 w-5" /> Write my study guide
          </button>
        </div>
      </form>

      <div :if={@saved_guides != []} class="p-8 lg:p-10">
        <h3 class="text-xl font-semibold text-primary">Your guides</h3>
        <p class="mt-1.5 text-sm text-body">
          Open one you've already written — keeping the story and the cheat sheet costs nothing.
        </p>

        <div class="mt-6 divide-y divide-black/5 border-t border-black/5">
          <div
            :for={guide <- @saved_guides}
            class="flex flex-wrap items-center justify-between gap-4 py-4"
          >
            <div class="min-w-0">
              <p class="truncate font-semibold text-ink">
                {guide.title || study_guide_style_label(guide.style)}
              </p>
              <p class="mt-0.5 text-sm text-muted">
                {study_guide_style_label(guide.style)} · {study_guide_depth_label(guide.depth)} · {study_guide_state_label(
                  guide
                )}
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <button
                type="button"
                phx-click="open-study-guide"
                phx-value-id={guide.id}
                class="inline-flex items-center gap-2 rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
              >
                Open <.icon name="hero-chevron-right" class="h-4 w-4" />
              </button>
              <button
                type="button"
                phx-click="delete-study-guide"
                phx-value-id={guide.id}
                data-confirm="Delete this study guide?"
                class="grid h-11 w-11 place-items-center rounded-2xl border border-black/10 text-muted transition hover:border-red-200 hover:bg-red-50 hover:text-red-600"
                aria-label="Delete this guide"
              >
                <.icon name="hero-trash" class="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :study_guide, :map, required: true
  slot :inner_block, required: true

  # Shared chrome for every face of an existing guide: back to the brief on the
  # left, what this guide was written as on the right.
  defp study_guide_shell(assigns) do
    ~H"""
    <div>
      <div class="flex flex-wrap items-center justify-between gap-4 border-b border-black/5 p-6 lg:px-10">
        <button
          type="button"
          phx-click="open-study-guide-brief"
          class="inline-flex items-center gap-2 rounded-2xl border border-black/10 px-5 py-3 text-sm font-semibold text-ink transition hover:border-primary/40 hover:bg-mint/40"
        >
          <.icon name="hero-arrow-left" class="h-4 w-4" /> Guide settings
        </button>

        <div class="flex flex-wrap items-center gap-2">
          <span class="rounded-full border border-black/10 px-4 py-2 text-xs font-semibold text-ink">
            {study_guide_style_label(@study_guide.style)}
          </span>
          <span class="rounded-full border border-black/10 px-4 py-2 text-xs font-semibold text-ink">
            {study_guide_reading_level_label(@study_guide.reading_level)}
          </span>
          <button
            type="button"
            phx-click="open-study-guide-brief"
            class="inline-flex items-center gap-1.5 rounded-2xl bg-primary px-5 py-3 text-sm font-semibold text-white transition hover:bg-ink"
          >
            <.icon name="hero-sparkles" class="h-4 w-4" /> Write another
          </button>
        </div>
      </div>

      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :study_guide, :map, required: true
  attr :scope_label, :string, required: true

  # The document itself: contents down the side on wide screens, the guide
  # itself in a reading column, and the glossary and takeaways closing it out.
  defp study_guide_document(assigns) do
    assigns = assign(assigns, :sections, assigns.study_guide.study_guide_sections)

    ~H"""
    <article class="p-8 lg:p-10">
      <header class="border-b border-black/5 pb-8">
        <p class="text-xs font-semibold uppercase tracking-wider text-muted">{@scope_label}</p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight text-primary sm:text-4xl">
          {@study_guide.title || "Your study guide"}
        </h1>
        <p :if={@study_guide.focus} class="mt-4 text-sm italic text-muted">
          Focused on: {@study_guide.focus}
        </p>
        <div :if={@study_guide.summary} class="mt-6 rounded-3xl bg-mint/40 p-6">
          <p class="text-xs font-semibold uppercase tracking-wider text-primary">The gist</p>
          <p class="mt-2 text-body">{@study_guide.summary}</p>
        </div>
      </header>

      <div class="mt-8 gap-10 lg:grid lg:grid-cols-[minmax(0,14rem)_minmax(0,1fr)]">
        <nav :if={length(@sections) > 1} class="mb-8 lg:mb-0">
          <p class="text-xs font-semibold uppercase tracking-wider text-muted">Contents</p>
          <ol class="mt-3 space-y-2 lg:sticky lg:top-8">
            <li :for={{section, index} <- Enum.with_index(@sections, 1)}>
              <a
                href={"##{study_guide_anchor(section)}"}
                class="flex gap-2 text-sm text-body transition hover:text-primary"
              >
                <span class="font-semibold text-muted">{index}.</span>
                <span>{section.heading}</span>
              </a>
            </li>
          </ol>
        </nav>

        <div class="min-w-0 space-y-10">
          <section :for={section <- @sections} id={study_guide_anchor(section)}>
            <h2 class="text-2xl font-semibold tracking-tight text-ink">{section.heading}</h2>

            <p
              :for={paragraph <- study_guide_paragraphs(section.body)}
              class="mt-4 leading-relaxed text-body"
            >
              {paragraph}
            </p>

            <ul :if={section.bullets != []} class="mt-4 space-y-2.5">
              <li :for={bullet <- section.bullets} class="flex gap-3 text-body">
                <.icon name="hero-check-circle" class="mt-0.5 h-5 w-5 shrink-0 text-primary" />
                <span>{bullet}</span>
              </li>
            </ul>

            <p
              :if={section.callout}
              class="mt-5 rounded-2xl bg-mint/40 p-5 text-sm font-medium text-ink"
            >
              <span class="mr-1.5 font-semibold text-primary">Key idea:</span>{section.callout}
            </p>
          </section>

          <section :if={@study_guide.key_terms != []} class="border-t border-black/5 pt-8">
            <h2 class="text-2xl font-semibold tracking-tight text-ink">Key terms</h2>
            <dl class="mt-4 grid gap-4 sm:grid-cols-2">
              <div
                :for={term <- @study_guide.key_terms}
                class="rounded-2xl border border-black/10 p-5"
              >
                <dt class="font-semibold text-primary">{term.term}</dt>
                <dd class="mt-1.5 text-sm text-body">{term.definition}</dd>
              </div>
            </dl>
          </section>

          <section :if={@study_guide.key_takeaways != []} class="border-t border-black/5 pt-8">
            <h2 class="text-2xl font-semibold tracking-tight text-ink">Before you move on</h2>
            <ul class="mt-4 space-y-3">
              <li
                :for={takeaway <- @study_guide.key_takeaways}
                class="flex gap-3 rounded-2xl bg-black/[0.03] p-4 text-body"
              >
                <.icon name="hero-sparkles" class="mt-0.5 h-5 w-5 shrink-0 text-primary" />
                <span>{takeaway}</span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </article>
    """
  end

  @doc """
  Default brief for a brand-new study guide — the same shape the brief form
  reads and writes, so `StudyHubLive` never hand-rolls it.
  """
  def default_study_guide_settings do
    %{
      style: :notes,
      depth: :standard,
      reading_level: :intermediate,
      include_examples: true,
      include_key_terms: true,
      focus: nil
    }
  end

  @doc "Reads a saved guide's brief back into the form, so \"Write another\" starts from the last one."
  def study_guide_settings_from(%Assessments.StudyGuide{} = study_guide) do
    %{
      style: study_guide.style,
      depth: study_guide.depth,
      reading_level: study_guide.reading_level,
      include_examples: study_guide.include_examples,
      include_key_terms: study_guide.include_key_terms,
      focus: study_guide.focus
    }
  end

  def study_guide_settings_from(nil), do: default_study_guide_settings()

  @doc "Style choices, with the copy the brief form shows for each."
  def study_guide_style_options do
    [
      {:notes, "Short notes", "Tight prose and bullets, nothing padded.", "hero-document-text"},
      {:story, "As a story", "One narrative you follow from start to finish.", "hero-book-open"},
      {:cheat_sheet, "Cheat sheet", "Scannable facts, rules and steps.", "hero-bolt"},
      {:q_and_a, "Q&A", "Every heading a question you'd actually ask.",
       "hero-chat-bubble-left-right"},
      {:analogies, "By analogy", "Everyday comparisons, then mapped back.", "hero-light-bulb"}
    ]
  end

  def study_guide_depth_options do
    [
      {:brief, "Brief", "a skim"},
      {:standard, "Standard", "a study session"},
      {:deep, "In depth", "the detail too"}
    ]
  end

  def study_guide_reading_level_options do
    [
      {:beginner, "New to this"},
      {:intermediate, "Some background"},
      {:advanced, "Practitioner"}
    ]
  end

  def study_guide_style_label(style) do
    Enum.find_value(study_guide_style_options(), "Study guide", fn {value, label, _blurb, _icon} ->
      if value == style, do: label
    end)
  end

  # Reads as "...writing it up as short notes" / "as a story", so the copy in
  # the waiting state names the style the learner actually chose.
  defp study_guide_style_phrase(:story), do: "a story"
  defp study_guide_style_phrase(:cheat_sheet), do: "a cheat sheet"
  defp study_guide_style_phrase(:q_and_a), do: "questions and answers"
  defp study_guide_style_phrase(:analogies), do: "a set of analogies"
  defp study_guide_style_phrase(_notes), do: "short notes"

  defp study_guide_depth_label(depth) do
    Enum.find_value(study_guide_depth_options(), "Standard", fn {value, label, _hint} ->
      if value == depth, do: label
    end)
  end

  defp study_guide_reading_level_label(level) do
    Enum.find_value(study_guide_reading_level_options(), "Some background", fn {value, label} ->
      if value == level, do: label
    end)
  end

  defp study_guide_state_label(%{status: status}) when status in [:pending, :processing],
    do: "Writing"

  defp study_guide_state_label(%{status: :failed}), do: "Failed"

  defp study_guide_state_label(%{sections_generated_count: count}) when is_integer(count),
    do: "#{count} #{if count == 1, do: "section", else: "sections"}"

  defp study_guide_state_label(_study_guide), do: "Ready"

  # The generator returns prose with blank lines between paragraphs, since it
  # is forbidden from returning markup — so paragraphing is ours to do.
  defp study_guide_paragraphs(nil), do: []

  defp study_guide_paragraphs(body) when is_binary(body),
    do: String.split(body, ~r/\n\s*\n/, trim: true)

  defp study_guide_anchor(%{id: id}) when not is_nil(id), do: "study-guide-section-#{id}"
  defp study_guide_anchor(%{position: position}), do: "study-guide-section-#{position}"
end
