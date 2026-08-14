defmodule WasomiWeb.StudyComponents do
  @moduledoc """
  Shared self-study review UI — quiz-taking (untimed and timed), flashcard
  review, and practice-question self-check — used by both `CoursePlayerLive`
  (the untimed Module Quiz panel) and `WasomiWeb.StudyHubLive` (Flashcards,
  Extra practice, and Timed quiz). Imported locally by each, not globally,
  since only these two LiveViews need it.
  """
  use Phoenix.Component

  alias Wasomi.Assessments

  import WasomiWeb.CoreComponents, only: [icon: 1]

  def timed_quiz_presets do
    [{"Relaxed", 90}, {"Standard", 60}, {"Quick", 30}]
  end

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

  def flashcard_set_panel(assigns) do
    ~H"""
    <div class="p-8 lg:p-10">
      <%= case @flashcard_set.status do %>
        <% status when status in [:pending, :processing] -> %>
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
                  This can happen if there aren't any readable lessons yet.
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
            cards={@flashcard_cards}
            index={@flashcard_index}
            flipped?={@flashcard_flipped?}
          />
      <% end %>
    </div>
    """
  end

  attr :cards, :list, required: true
  attr :index, :integer, required: true
  attr :flipped?, :boolean, required: true

  defp flashcard_review(assigns) do
    total = length(assigns.cards)
    known_count = Enum.count(assigns.cards, &(&1.progress && &1.progress.status == :known))

    assigns = assign(assigns, total: total, known_count: known_count)

    ~H"""
    <%= if @cards == [] do %>
      <div class="grid min-h-[320px] place-items-center text-center text-muted">
        There aren't any flashcards here yet.
      </div>
    <% else %>
      <%= if @index >= @total do %>
        <div class="grid min-h-[320px] place-items-center text-center">
          <div>
            <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-mint text-primary">
              <.icon name="hero-check-circle" class="h-8 w-8" />
            </span>
            <h3 class="mt-4 text-2xl font-bold text-ink">Deck complete!</h3>
            <p class="mt-2 text-body">You know {@known_count} of {@total} cards.</p>
            <div class="mt-6 flex flex-wrap justify-center gap-3">
              <button
                :if={@known_count < @total}
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
        <div class="flex items-center justify-between text-xs text-muted">
          <span>Card {@index + 1} of {@total}</span>
          <span>{@known_count} known of {@total}</span>
        </div>
        <div class="mt-2 h-1.5 overflow-hidden rounded-full bg-mint">
          <div
            class="h-full rounded-full bg-primary transition-all duration-300"
            style={"width: #{round((@index + 1) / @total * 100)}%"}
          >
          </div>
        </div>

        <button
          type="button"
          phx-click="flip-flashcard"
          class="mt-6 block h-72 w-full [perspective:1200px]"
        >
          <div class={[
            "relative h-full w-full rounded-2xl transition-transform duration-500 [transform-style:preserve-3d]",
            @flipped? && "[transform:rotateY(180deg)]"
          ]}>
            <div class="absolute inset-0 flex flex-col items-center justify-center rounded-2xl border border-black/5 bg-soft p-8 text-center [backface-visibility:hidden]">
              <span class="text-xs font-semibold uppercase tracking-wider text-primary">
                Question
              </span>
              <p class="mt-3 text-xl font-medium leading-snug text-ink">{entry.flashcard.front}</p>
              <span class="mt-4 text-xs text-muted">Tap to reveal the answer</span>
            </div>
            <div class="absolute inset-0 flex flex-col items-center justify-center rounded-2xl border border-primary/20 bg-mint p-8 text-center [backface-visibility:hidden] [transform:rotateY(180deg)]">
              <span class="text-xs font-semibold uppercase tracking-wider text-primary">Answer</span>
              <p class="mt-3 text-lg leading-relaxed text-ink">{entry.flashcard.back}</p>
            </div>
          </div>
        </button>

        <div class="mt-6 flex items-center justify-between gap-3">
          <button
            type="button"
            phx-click="flashcard-prev"
            disabled={@index == 0}
            class="inline-flex items-center gap-1.5 rounded-full border border-black/10 px-5 py-2.5 text-sm font-semibold text-ink transition hover:bg-mint disabled:cursor-not-allowed disabled:opacity-40"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back
          </button>
          <div class="flex gap-3">
            <button
              type="button"
              phx-click="rate-flashcard"
              phx-value-rating="review_again"
              class="rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-semibold text-ink transition hover:border-red-200 hover:bg-red-50 hover:text-red-600"
            >
              Review again
            </button>
            <button
              type="button"
              phx-click="rate-flashcard"
              phx-value-rating="known"
              class="rounded-full bg-primary px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-ink"
            >
              Know it
            </button>
          </div>
        </div>
      <% end %>
    <% end %>
    """
  end

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

  defp result_passed?(%{passed: passed}), do: passed
  defp result_passed?(%Assessments.QuizSubmission{passed: passed}), do: passed
  defp result_passed?(_), do: false

  defp result_score(%{score_percent: score}), do: score
  defp result_score(%Assessments.QuizSubmission{score_percent: score}), do: score
  defp result_score(_), do: 0

  defp preview_result?(%{preview?: preview?}), do: preview?
  defp preview_result?(%Assessments.QuizSubmission{}), do: false
  defp preview_result?(_), do: false
end
