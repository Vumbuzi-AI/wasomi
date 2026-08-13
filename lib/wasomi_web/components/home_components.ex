defmodule WasomiWeb.HomeComponents do
  use Phoenix.Component
  use Gettext, backend: WasomiWeb.Gettext

  import WasomiWeb.CoreComponents, only: [show: 2, hide: 2]

  alias Phoenix.LiveView.JS
  alias Wasomi.Catalog

  @popular_search_topics [
    "GS1 Barcode Basics",
    "GTIN Foundations",
    "Product Data Quality",
    "Traceability"
  ]

  def announcement_bar(assigns) do
    ~H"""
    <div class="bg-secondary py-2.5 text-white">
      <div class="mx-auto flex max-w-container flex-wrap items-center justify-center gap-x-3 gap-y-1 px-5 text-center lg:px-8">
        <span class="rounded-full bg-primary px-2.5 py-0.5 text-[11px] font-bold uppercase tracking-wide">
          New
        </span>
        <p class="text-sm">Learn GS1 Digital Link with practical examples.</p>
        <a
          href="/courses"
          class="group inline-flex items-center gap-1 text-sm font-medium hover:text-primary"
        >
          View course
          <svg
            class="h-3.5 w-3.5 transition group-hover:translate-x-0.5"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <line x1="5" y1="12" x2="19" y2="12" /><polyline points="12 5 19 12 12 19" />
          </svg>
        </a>
      </div>
    </div>
    """
  end

  attr :current_user, :map, default: nil

  def home_header(assigns) do
    assigns = assign(assigns, :popular_search_topics, @popular_search_topics)

    ~H"""
    <header class="sticky top-0 z-50 border-b border-black/5 bg-white">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <nav class="flex items-center justify-between gap-4 py-4">
          <a href="/" class="flex items-center">
            <img src="/images/logo.png" alt="Wasomi" class="h-8 w-auto sm:h-9" />
          </a>
          
    <!-- Drives the mobile nav menu and hamburger icon via peer-checked, no JS. -->
          <input type="checkbox" id="nav-toggle" class="peer hidden" />

          <div class="absolute left-4 right-4 top-16 hidden flex-col gap-1 rounded-2xl border border-black/5 bg-white p-4 shadow-xl peer-checked:flex lg:static lg:flex lg:flex-row lg:items-center lg:gap-8 lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none">
            <a href="/#courses" class="py-2 font-medium text-dark transition hover:text-primary">
              Courses
            </a>
            <a href="#how-it-works" class="py-2 font-medium text-dark transition hover:text-primary">
              How it works
            </a>
            <a href="#mentors" class="py-2 font-medium text-dark transition hover:text-primary">
              Instructors
            </a>
          </div>

          <div class="flex items-center gap-3">
            <a
              :if={@current_user}
              href={home_destination_path(@current_user)}
              class="hidden items-center rounded-full border border-dark px-5 py-2 text-sm font-medium text-dark transition hover:bg-dark hover:text-white sm:inline-flex"
            >
              {home_destination_label(@current_user)}
            </a>
            <button
              type="button"
              phx-click={open_search()}
              class="hidden items-center gap-1.5 rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-dark sm:inline-flex"
            >
              <svg
                class="h-4 w-4 shrink-0 text-primary"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
              </svg>
              Search
            </button>
            <a
              :if={!@current_user}
              href="/users/log_in"
              class="group hidden items-center gap-1.5 rounded-full border border-dark px-5 py-2 text-sm font-medium text-dark transition hover:bg-dark hover:text-white sm:inline-flex"
            >
              Login
              <svg
                class="h-3.5 w-3.5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
              </svg>
            </a>
            <label
              for="nav-toggle"
              class="grid h-11 w-11 cursor-pointer place-items-center rounded-full border border-black/10 lg:hidden"
            >
              <svg
                class="h-5 w-5 text-dark"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
              >
                <line x1="3" y1="7" x2="21" y2="7" /><line x1="3" y1="12" x2="21" y2="12" /><line
                  x1="3"
                  y1="17"
                  x2="21"
                  y2="17"
                />
              </svg>
            </label>
          </div>
        </nav>
      </div>

      <div
        id="search-backdrop"
        class="fixed inset-0 z-40 hidden bg-dark/40"
        phx-click={close_search()}
      >
      </div>

      <div
        id="search-panel"
        class="absolute inset-x-0 top-full z-50 hidden px-5 pt-2 lg:px-8"
        phx-click-away={close_search()}
        phx-window-keydown={close_search()}
        phx-key="escape"
      >
        <div class="mx-auto max-w-2xl rounded-2xl bg-white p-6 shadow-2xl">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="text-xs font-bold uppercase tracking-wide text-primary">Find a course</p>
              <h2 class="mt-1 text-xl font-semibold text-dark">What do you want to learn?</h2>
            </div>
            <button
              type="button"
              phx-click={close_search()}
              aria-label="Close search"
              class="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-black/10 text-dark transition hover:border-dark"
            >
              <svg
                class="h-4 w-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>

          <form
            action="/courses"
            method="get"
            class="mt-5 flex items-center gap-2 rounded-full border-2 border-primary px-5 py-3"
          >
            <svg
              class="h-5 w-5 shrink-0 text-primary"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
            <input
              type="search"
              name="search"
              id="search-panel-input"
              placeholder="Search courses or topics"
              class="w-full border-0 bg-transparent p-0 text-sm text-dark placeholder:text-muted focus:outline-none focus:ring-0"
            />
            <button
              type="submit"
              class="shrink-0 rounded-full bg-soft px-4 py-2 text-sm font-medium text-dark transition hover:bg-dark hover:text-white"
            >
              Search
            </button>
          </form>

          <div class="mt-5">
            <p class="text-xs font-semibold text-muted">Popular now</p>
            <div class="mt-3 flex flex-wrap gap-2">
              <a
                :for={topic <- @popular_search_topics}
                href={"/courses?search=#{URI.encode_www_form(topic)}"}
                class="rounded-full border border-black/10 px-4 py-2 text-sm font-medium text-dark transition hover:border-dark"
              >
                {topic}
              </a>
            </div>
          </div>
        </div>
      </div>
    </header>
    """
  end

  defp open_search(js \\ %JS{}) do
    js
    |> JS.show(to: "#search-backdrop")
    |> show("#search-panel")
    |> JS.focus(to: "#search-panel-input")
  end

  defp close_search(js \\ %JS{}) do
    js
    |> JS.hide(to: "#search-backdrop")
    |> hide("#search-panel")
  end

  defp home_destination_path(%{role: :admin}), do: "/admin"
  defp home_destination_path(_user), do: "/dashboard"

  defp home_destination_label(%{role: :admin}), do: "Admin dashboard"
  defp home_destination_label(_user), do: "My dashboard"

  def hero(assigns) do
    ~H"""
    <section class="relative isolate min-h-[560px] overflow-hidden bg-dark lg:min-h-[640px]">
      <img
        src="/images/hero-home.png"
        alt=""
        aria-hidden="true"
        class="absolute inset-0 h-full w-full animate-image-in object-cover"
      />
      <div class="relative mx-auto flex min-h-[560px] max-w-container items-center px-5 py-16 lg:min-h-[640px] lg:px-8">
        <div class="max-w-2xl animate-fade-up opacity-0">
          <h1 class="max-w-lg text-4xl font-semibold leading-[1.1] text-white sm:text-5xl lg:text-6xl">
            Learn the standards behind <span class="text-primary">trusted products.</span>
          </h1>
          <p class="mt-6 max-w-md text-lg text-white/80">
            Build practical GS1 skills in barcodes, product identification, data quality and traceability.
          </p>
          <div class="mt-8 flex flex-wrap items-center gap-4">
            <a
              href="/users/register"
              class="group inline-flex items-center gap-2 rounded-full bg-primary py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-white hover:text-primary"
            >
              Get Started
              <span class="grid h-9 w-9 place-items-center rounded-full bg-white text-primary transition group-hover:bg-primary group-hover:text-white">
                <svg
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
                </svg>
              </span>
            </a>
            <a
              href="/courses"
              class="group inline-flex items-center gap-2 rounded-full border border-white/30 py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-white hover:text-dark"
            >
              Explore Course Paths
              <span class="grid h-9 w-9 place-items-center rounded-full bg-white/10 text-white transition group-hover:bg-dark group-hover:text-white">
                <svg
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
                </svg>
              </span>
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def about_wasomi(assigns) do
    ~H"""
    <section class="bg-white py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid items-center gap-12 lg:grid-cols-2">
          <div
            id="about-box"
            phx-hook="RevealOnScroll"
            data-reveal="settle-float"
            class="flex origin-bottom-left -translate-x-12 -rotate-6 justify-center opacity-0 transition-all duration-700 [transition-timing-function:cubic-bezier(0.2,0,0,1)]"
          >
            <img src="/images/gs1-box.png" alt="GS1-labeled shipping box" class="w-full max-w-md" />
          </div>
          <div id="about-content" phx-hook="RevealOnScroll" class="opacity-0">
            <h2 class="text-4xl font-bold text-dark sm:text-5xl">About Wasomi</h2>
            <p class="mt-6 max-w-xl text-body">
              Wasomi turns GS1 standards into clear, practical lessons. Learn how barcodes, product
              identification, data quality, and traceability work, then use that knowledge in real
              business situations.
            </p>
            <div class="mt-10 grid grid-cols-2 gap-8">
              <div class="border-t-2 border-dark pt-4">
                <p class="font-bold text-dark">Learn clearly</p>
                <p class="mt-1 text-sm text-body">Short, focused GS1 lessons</p>
              </div>
              <div class="border-t-2 border-dark pt-4">
                <p class="font-bold text-dark">Apply confidently</p>
                <p class="mt-1 text-sm text-body">Examples built around real products</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def gs1_in_action(assigns) do
    ~H"""
    <section class="bg-white py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="text-center">
          <h2 class="text-4xl font-bold text-dark sm:text-5xl">See GS1 in action</h2>
          <p class="mt-4 text-body">Select a step to see how Wasomi makes GS1 standards practical.</p>
        </div>

        <div class="mx-auto mt-10 max-w-5xl">
          <input type="radio" name="gs1-step" id="gs1-step-1" class="peer/s1 sr-only" checked />
          <input type="radio" name="gs1-step" id="gs1-step-2" class="peer/s2 sr-only" />
          <input type="radio" name="gs1-step" id="gs1-step-3" class="peer/s3 sr-only" />
          <input type="radio" name="gs1-step" id="gs1-step-4" class="peer/s4 sr-only" />

          <div class="mb-6 grid grid-cols-2 divide-x divide-black/10 border border-black/10 sm:grid-cols-4">
            <label
              for="gs1-step-1"
              class="cursor-pointer border-b border-black/10 px-5 py-4 text-center text-sm font-semibold text-dark transition peer-checked/s1:border-b-0 peer-checked/s1:bg-dark peer-checked/s1:text-white sm:border-b-0"
            >
              <span class="text-primary peer-checked/s1:text-primary">01</span> Identify
            </label>
            <label
              for="gs1-step-2"
              class="cursor-pointer border-b border-black/10 px-5 py-4 text-center text-sm font-semibold text-dark transition peer-checked/s2:border-b-0 peer-checked/s2:bg-dark peer-checked/s2:text-white sm:border-b-0"
            >
              <span class="text-primary">02</span> Capture
            </label>
            <label
              for="gs1-step-3"
              class="cursor-pointer px-5 py-4 text-center text-sm font-semibold text-dark transition peer-checked/s3:bg-dark peer-checked/s3:text-white"
            >
              <span class="text-primary">03</span> Share
            </label>
            <label
              for="gs1-step-4"
              class="cursor-pointer px-5 py-4 text-center text-sm font-semibold text-dark transition peer-checked/s4:bg-dark peer-checked/s4:text-white"
            >
              <span class="text-primary">04</span> Verify
            </label>
          </div>

          <div class="hidden border border-black/10 -mx-6 sm:-mx-10 lg:grid-cols-2 peer-checked/s1:grid peer-checked/s1:animate-fade-up">
            <.gs1_step_visual>
              <.gs1_step_icon>
                <path d="M7 7h.01M3 11V5a2 2 0 0 1 2-2h6l10 10-8 8L3 11Z" />
              </.gs1_step_icon>
            </.gs1_step_visual>
            <.gs1_step_content
              eyebrow="Step 01 · Identify"
              title="Give every product a clear identity"
              description="A GTIN identifies the product so businesses can refer to the same item without confusion."
              checklist="Product identified"
              next="gs1-step-2"
            />
          </div>

          <div class="hidden border border-black/10 -mx-6 sm:-mx-10 lg:grid-cols-2 peer-checked/s2:grid peer-checked/s2:animate-fade-up">
            <.gs1_step_visual>
              <.gs1_step_icon>
                <path d="M4 7V4h3M20 7V4h-3M4 17v3h3M20 17v3h-3M9 8v8M12 8v8M15 8v8" />
              </.gs1_step_icon>
            </.gs1_step_visual>
            <.gs1_step_content
              eyebrow="Step 02 · Capture"
              title="Capture product data accurately"
              description="A barcode carries the identifier so the right information can be captured quickly and consistently."
              checklist="Barcode ready to scan"
              next="gs1-step-3"
            />
          </div>

          <div class="hidden border border-black/10 -mx-6 sm:-mx-10 lg:grid-cols-2 peer-checked/s3:grid peer-checked/s3:animate-fade-up">
            <.gs1_step_visual>
              <.gs1_step_icon>
                <circle cx="6" cy="12" r="2.5" /><circle cx="18" cy="6" r="2.5" /><circle
                  cx="18"
                  cy="18"
                  r="2.5"
                /><path d="M8.2 10.8 15.8 7.2M8.2 13.2l7.6 3.6" />
              </.gs1_step_icon>
            </.gs1_step_visual>
            <.gs1_step_content
              eyebrow="Step 03 · Share"
              title="Share trusted data with partners"
              description="Standard product information helps trading partners work from the same reliable source."
              checklist="Data ready to share"
              next="gs1-step-4"
            />
          </div>

          <div class="hidden border border-black/10 -mx-6 sm:-mx-10 lg:grid-cols-2 peer-checked/s4:grid peer-checked/s4:animate-fade-up">
            <.gs1_step_visual>
              <.gs1_step_icon>
                <path d="M21 8 12 3 3 8l9 5 9-5Z" /><path d="M3 8v8l9 5 9-5V8" /><path d="m9 15 2 2 4-4" />
              </.gs1_step_icon>
            </.gs1_step_visual>
            <.gs1_step_content
              eyebrow="Step 04 · Verify"
              title="Verify products across the journey"
              description="Consistent identifiers make it easier to check a product from production to the final destination."
              checklist="Product journey verified"
              next="gs1-step-1"
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  slot :inner_block, required: true

  defp gs1_step_visual(assigns) do
    ~H"""
    <div class="flex flex-col justify-center gap-5 bg-dark px-8 py-12 lg:py-0">
      <span class="grid h-14 w-14 place-items-center rounded-xl border-2 border-white/40 text-white">
        {render_slot(@inner_block)}
      </span>
      <div>
        <p class="font-semibold text-white">Sample product</p>
        <p class="mt-1 text-sm text-white/60">GTIN 0614141000015</p>
      </div>
      <.gs1_barcode />
    </div>
    """
  end

  defp gs1_barcode(assigns) do
    ~H"""
    <div class="flex h-10 items-end gap-[2px]">
      <span class="h-full w-[3px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[3px] bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
      <span class="h-full w-[3px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[3px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[3px] bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-px bg-white"></span>
      <span class="h-full w-[2px] bg-white"></span>
    </div>
    """
  end

  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :checklist, :string, required: true
  attr :next, :string, required: true
  attr :next_label, :string, default: "Next step"

  defp gs1_step_content(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-5 px-8 py-12 text-center lg:py-16">
      <p class="text-sm font-bold uppercase tracking-wide text-primary">{@eyebrow}</p>
      <h3 class="max-w-sm text-3xl font-bold text-dark sm:text-4xl">{@title}</h3>
      <p class="max-w-md text-body">{@description}</p>
      <p class="flex items-center gap-2 font-semibold text-dark">
        <svg
          class="h-5 w-5 text-primary"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <polyline points="20 6 9 17 4 12" />
        </svg>
        {@checklist}
      </p>
      <label
        for={@next}
        class="group inline-flex cursor-pointer items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
      >
        {@next_label}
        <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark">
          <svg
            class="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <line x1="5" y1="12" x2="19" y2="12" /><polyline points="12 5 19 12 12 19" />
          </svg>
        </span>
      </label>
    </div>
    """
  end

  slot :inner_block, required: true

  defp gs1_step_icon(assigns) do
    ~H"""
    <svg
      class="h-7 w-7"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr :courses, :list, default: []

  def top_courses_section(assigns) do
    ~H"""
    <section id="courses" class="bg-slate-50 py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <h2 class="mx-auto max-w-2xl text-center text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
          Build practical GS1 skills
        </h2>
        <p class="mx-auto mt-4 max-w-2xl text-center text-body">
          Compare clear course outcomes, see what each course covers and choose the right place to
          start.
        </p>

        <div :if={@courses != []} class="mt-14 grid gap-7 md:grid-cols-2 lg:grid-cols-3">
          <.course_card :for={course <- Enum.take(@courses, 3)} course={course} />
        </div>

        <div
          :if={@courses == []}
          class="mx-auto mt-14 max-w-xl rounded-3xl border border-black/5 bg-white p-10 text-center"
        >
          <h3 class="text-xl font-semibold text-dark">New courses are on the way.</h3>
          <p class="mt-2 text-body">Published courses will appear here automatically.</p>
        </div>

        <div :if={length(@courses) > 3} class="mt-12 text-center">
          <a
            href="/courses"
            class="group inline-flex items-center gap-2 rounded-full border border-dark py-1.5 pl-6 pr-1.5 font-medium text-dark transition hover:bg-dark hover:text-white"
          >
            Explore All Courses
            <span class="grid h-9 w-9 place-items-center rounded-full bg-dark text-white transition group-hover:bg-primary">
              <svg
                class="h-4 w-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
              </svg>
            </span>
          </a>
        </div>
      </div>
    </section>
    """
  end

  def gs1_in_workplaces(assigns) do
    ~H"""
    <section class="bg-white py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-end">
          <h2 class="max-w-md text-4xl font-bold leading-[1.1] text-dark sm:text-5xl">
            Use GS1 skills in real workplaces.
          </h2>
          <p class="text-body sm:text-right">
            See where the standards you learn on Wasomi show up every day.
          </p>
        </div>

        <div class="mt-10 grid grid-cols-1 divide-y divide-white/10 border border-black/10 sm:grid-cols-2 sm:divide-x sm:divide-y-0 lg:grid-cols-4">
          <div class="bg-dark p-10 lg:p-14">
            <div class="flex items-center justify-between text-primary">
              <svg
                class="h-9 w-9"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M3 9.5 12 4l9 5.5" /><path d="M5 9.5V20h14V9.5" /><path d="M9.5 20v-6h5v6" />
              </svg>
              <span class="text-base font-bold">01</span>
            </div>
            <h3 class="mt-16 text-2xl font-bold text-white">Retail</h3>
            <p class="mt-3 text-base text-white/70">
              Identify products and improve checkout accuracy.
            </p>
          </div>

          <div class="bg-dark p-10 lg:p-14">
            <div class="flex items-center justify-between text-primary">
              <svg
                class="h-9 w-9"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M12 20.5S4 16 4 10a4 4 0 0 1 8-1.5A4 4 0 0 1 20 10c0 6-8 10.5-8 10.5Z" /><path d="M8.5 12h1.5l1-2 2 4 1-2h1.5" />
              </svg>
              <span class="text-base font-bold">02</span>
            </div>
            <h3 class="mt-16 text-2xl font-bold text-white">Healthcare</h3>
            <p class="mt-3 text-base text-white/70">
              Support safer identification of medicines and devices.
            </p>
          </div>

          <div class="bg-dark p-10 lg:p-14">
            <div class="flex items-center justify-between text-primary">
              <svg
                class="h-9 w-9"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M3 8.5 12 4l9 4.5-9 4.5-9-4.5Z" /><path d="M3 8.5V16l9 4.5 9-4.5V8.5" /><circle
                  cx="16.5"
                  cy="15.5"
                  r="2.25"
                /><path d="m18.7 17.7 1.8 1.8" />
              </svg>
              <span class="text-base font-bold">03</span>
            </div>
            <h3 class="mt-16 text-2xl font-bold text-white">Logistics</h3>
            <p class="mt-3 text-base text-white/70">
              Track cartons, pallets and movement across locations.
            </p>
          </div>

          <div class="bg-dark p-10 lg:p-14">
            <div class="flex items-center justify-between text-primary">
              <svg
                class="h-9 w-9"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M4 4v16h16" /><path d="M7 15.5 11 11l3 3 5-6" />
              </svg>
              <span class="text-base font-bold">04</span>
            </div>
            <h3 class="mt-16 text-2xl font-bold text-white">Manufacturing</h3>
            <p class="mt-3 text-base text-white/70">
              Build traceability into production and distribution.
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def how_it_works(assigns) do
    ~H"""
    <section id="how-it-works" class="bg-slate-50 py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="text-center">
          <h2 class="text-4xl font-bold text-dark sm:text-5xl">How it works</h2>
          <p class="mx-auto mt-4 max-w-xl text-body">
            Choose a course, learn each standard, practise and finish with proof of completion.
          </p>
        </div>

        <div
          id="how-it-works-steps"
          phx-hook="RevealOnScroll"
          data-reveal="stagger"
          class="group mx-auto mt-14 max-w-4xl divide-y divide-black/10 border-y border-black/10"
        >
          <.how_it_works_step
            number="1"
            title="Choose a course"
            description="Browse by skill area, level, duration and certificate availability."
            active
          >
            <circle cx="12" cy="12" r="9" /><path d="m14.5 9.5-1.8 4.2-4.2 1.8 1.8-4.2 4.2-1.8Z" />
          </.how_it_works_step>

          <.how_it_works_step
            number="2"
            title="Follow lessons"
            description="Move through structured lessons with clear modules and next steps."
          >
            <rect x="3" y="4" width="18" height="12" rx="2" /><path d="M9 20h6M12 16v4" /><path d="M10.5 8.5v3l2.5-1.5-2.5-1.5Z" />
          </.how_it_works_step>

          <.how_it_works_step
            number="3"
            title="Complete practice"
            description="Use tasks and checks to turn lessons into real understanding."
          >
            <rect x="6" y="4" width="12" height="16" rx="2" /><rect
              x="9"
              y="2.5"
              width="6"
              height="3"
              rx="1"
            /><path d="M9 11h6M9 15h4" />
          </.how_it_works_step>

          <.how_it_works_step
            number="4"
            title="Track progress"
            description="See what is complete, what is next and what remains."
          >
            <path d="M4 19V5M4 19h16" /><path d="m7 14 3-3 3 2 4-5" />
          </.how_it_works_step>

          <.how_it_works_step
            number="5"
            title="Earn proof"
            description="Finish the required lessons and unlock completion status or a certificate."
            last
          >
            <circle cx="12" cy="9" r="5" /><path d="m8.5 13-1.5 7 5-3 5 3-1.5-7" />
          </.how_it_works_step>
        </div>
      </div>
    </section>
    """
  end

  attr :number, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :active, :boolean, default: false
  attr :last, :boolean, default: false
  slot :inner_block, required: true

  defp how_it_works_step(assigns) do
    assigns = assign(assigns, :delay_ms, (String.to_integer(assigns.number) - 1) * 120)

    ~H"""
    <div
      class="group-[.in-view]:animate-fade-up grid grid-cols-[auto_1fr_auto] items-stretch gap-6 py-6 opacity-0"
      style={"animation-delay: #{@delay_ms}ms"}
    >
      <div class="flex flex-col items-center">
        <span class={[
          "grid h-10 w-10 shrink-0 place-items-center rounded-full text-sm font-bold",
          @active && "bg-primary text-white",
          !@active && "border-2 border-dark text-dark"
        ]}>
          {@number}
        </span>
        <span :if={!@last} class="mt-2 w-0.5 flex-1 bg-dark"></span>
      </div>

      <div class="self-center">
        <h3 class="font-bold text-dark">{@title}</h3>
        <p class="mt-1 text-sm text-body">{@description}</p>
      </div>

      <div class={[
        "grid h-11 w-11 shrink-0 place-items-center self-center rounded-xl border",
        @active && "border-primary text-primary",
        !@active && "border-black/10 text-dark"
      ]}>
        <svg
          class="h-5 w-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          {render_slot(@inner_block)}
        </svg>
      </div>
    </div>
    """
  end

  def certificates(assigns) do
    ~H"""
    <section class="bg-white py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid items-center gap-16 lg:grid-cols-2">
          <div>
            <h2 class="max-w-md text-4xl font-bold leading-[1.1] text-dark sm:text-5xl">
              Earn a certificate after completing a course.
            </h2>
            <p class="mt-4 max-w-md text-body">
              Keep a clear record of the course, learner, completion date and certificate number.
            </p>
            <ul class="mt-6 space-y-3">
              <li class="flex items-center gap-2.5 text-sm font-semibold text-dark">
                <svg
                  class="h-5 w-5 shrink-0 text-primary"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="12" cy="12" r="9" /><polyline points="8.5 12.5 11 15 15.5 9" />
                </svg>
                Course title
              </li>
              <li class="flex items-center gap-2.5 text-sm font-semibold text-dark">
                <svg
                  class="h-5 w-5 shrink-0 text-primary"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="12" cy="12" r="9" /><polyline points="8.5 12.5 11 15 15.5 9" />
                </svg>
                Learner name
              </li>
              <li class="flex items-center gap-2.5 text-sm font-semibold text-dark">
                <svg
                  class="h-5 w-5 shrink-0 text-primary"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="12" cy="12" r="9" /><polyline points="8.5 12.5 11 15 15.5 9" />
                </svg>
                Completion record
              </li>
            </ul>
          </div>

          <div class="flex justify-center">
            <div class="relative w-full max-w-lg -rotate-1 rounded-xl bg-dark p-2 shadow-2xl">
              <span class="absolute -left-1 top-6 h-1.5 w-6 rounded-full bg-primary"></span>
              <span class="absolute -right-1 bottom-6 h-1.5 w-6 rounded-full bg-primary"></span>

              <div class="relative rounded-lg border border-primary/40 bg-white px-6 py-5">
                <div class="flex items-center justify-between border-b border-black/10 pb-3">
                  <div class="flex items-center gap-2">
                    <img src="/images/logo.png" alt="" class="h-5 w-auto" />
                    <span class="text-[10px] font-semibold uppercase tracking-wide text-muted">
                      GS1 Learning
                    </span>
                  </div>
                  <svg
                    class="h-5 w-5 text-primary"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <circle cx="12" cy="8" r="5" /><path d="m8.5 12.5-1.5 7 5-3 5 3-1.5-7" />
                  </svg>
                </div>

                <div class="relative overflow-hidden py-8 text-center">
                  <span class="pointer-events-none absolute inset-0 flex items-center justify-end pr-2 text-[130px] font-black leading-none text-dark/5">
                    W
                  </span>
                  <p class="relative text-xs font-bold uppercase tracking-wide text-primary">
                    Certificate of Completion
                  </p>
                  <p class="relative mt-3 text-xs text-muted">This confirms that</p>
                  <p class="relative mt-1 font-serif text-3xl text-dark">Your Name</p>
                  <p class="relative mt-3 text-xs text-muted">has completed</p>
                  <p class="relative mt-1 font-semibold text-dark">GS1 Barcode Basics</p>
                </div>

                <div class="flex items-end justify-between border-t border-black/10 pt-3">
                  <div>
                    <p class="text-[10px] uppercase tracking-wide text-muted">Completion date</p>
                    <p class="text-sm font-medium text-dark">DD / MM / YYYY</p>
                  </div>
                  <div class="flex h-6 items-end gap-[2px]">
                    <span class="h-full w-[2px] bg-dark"></span>
                    <span class="h-full w-px bg-dark"></span>
                    <span class="h-full w-[2px] bg-dark"></span>
                    <span class="h-full w-px bg-dark"></span>
                    <span class="h-full w-[2px] bg-dark"></span>
                    <span class="h-full w-px bg-dark"></span>
                    <span class="h-full w-[2px] bg-dark"></span>
                    <span class="h-full w-px bg-dark"></span>
                    <span class="h-full w-[2px] bg-dark"></span>
                  </div>
                  <div class="text-right">
                    <p class="text-[10px] uppercase tracking-wide text-muted">Issued by</p>
                    <p class="text-sm font-medium text-dark">Wasomi</p>
                  </div>
                </div>
              </div>

              <div class="absolute -bottom-4 -right-4 grid h-14 w-14 place-items-center rounded-full bg-dark text-white shadow-lg">
                <div class="text-center leading-none">
                  <svg
                    class="mx-auto h-3.5 w-3.5 text-primary"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                  <p class="mt-1 text-[7px] font-bold uppercase tracking-wide">Verified</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :course, :map, required: true
  attr :image_class, :string, default: "h-56"
  attr :title_class, :string, default: "text-ink"

  def course_card(assigns) do
    ~H"""
    <a
      href={"/courses/#{@course.slug}"}
      class="group block overflow-hidden rounded-3xl border border-black/5 bg-white shadow-sm transition duration-300 hover:-translate-y-1 hover:shadow-xl"
    >
      <div class="overflow-hidden bg-mint">
        <img
          loading="lazy"
          src={@course.thumbnail_key}
          alt=""
          class={[@image_class, "w-full object-cover transition duration-500 group-hover:scale-105"]}
        />
      </div>
      <div class="p-6">
        <div class="flex items-center justify-between gap-4">
          <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
            Course
          </span>
          <div class="text-lg font-semibold text-ink">
            {Catalog.format_price(@course)}
          </div>
        </div>
        <h3 class={["mt-4 text-lg font-medium", @title_class]}>{@course.title}</h3>
        <p class="mt-3 line-clamp-2 text-sm leading-6 text-body">{@course.description}</p>
        <div class="mt-5 flex flex-wrap items-center gap-5 text-sm text-body">
          <span class="flex items-center gap-2">
            <svg
              class="h-5 w-5 text-muted"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" />
            </svg>
            {format_duration(Catalog.duration_seconds(@course))}
          </span>
          <span class="flex items-center gap-2">
            <svg
              class="h-5 w-5 text-muted"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" />
            </svg>
            {lecture_label(Catalog.lecture_count(@course))}
          </span>
        </div>
      </div>
    </a>
    """
  end

  defp format_duration(seconds) when is_integer(seconds) and seconds > 0 do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)

    cond do
      hours > 0 and minutes > 0 -> "#{hours}hr #{minutes}min"
      hours > 0 -> "#{hours}hr"
      true -> "#{minutes}min"
    end
  end

  defp format_duration(_seconds), do: "0min"

  defp lecture_label(1), do: "1 lecture"
  defp lecture_label(count), do: "#{count} lectures"

  def mentors(assigns) do
    assigns =
      assign(assigns, :mentors, [
        %{
          name: "Matthew Ryan",
          role: "Product Designer",
          image:
            "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=600&q=80",
          class: ""
        },
        %{
          name: "James Michael",
          role: "Digital Marketer",
          image:
            "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=600&q=80",
          class: "sm:mt-12"
        },
        %{
          name: "Daniel Joseph",
          role: "Software Engineer",
          image:
            "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=600&q=80",
          class: ""
        },
        %{
          name: "Anthony Mark",
          role: "Project Manager",
          image:
            "https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=600&q=80",
          class: "sm:mt-12"
        }
      ])

    ~H"""
    <section id="mentors" class="bg-dark py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="flex flex-col items-start justify-between gap-6 sm:flex-row sm:items-end">
          <h2 class="max-w-xl text-3xl font-semibold text-white sm:text-4xl">
            Learn from the Best Talent in the Industry
          </h2>
          <a
            href="#"
            class="group inline-flex items-center gap-2 rounded-full border border-white/30 py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-white hover:text-dark"
          >
            View All Mentors
            <span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition">
              <svg
                class="h-4 w-4"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
              </svg>
            </span>
          </a>
        </div>
        <div class="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          <.mentor_card :for={mentor <- @mentors} mentor={mentor} />
        </div>
      </div>
    </section>
    """
  end

  attr :mentor, :map, required: true

  def mentor_card(assigns) do
    ~H"""
    <div class={["group relative aspect-[3/4] overflow-hidden rounded-3xl", @mentor.class]}>
      <img
        loading="lazy"
        src={@mentor.image}
        alt={@mentor.name}
        class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
      />
      <div class="absolute inset-x-0 bottom-0 p-5 [text-shadow:_0_2px_14px_rgb(0_0_0_/_0.75)]">
        <h3 class="text-lg font-medium text-white">{@mentor.name}</h3>
        <p class="text-sm text-white/85">{@mentor.role}</p>
        <div class="mt-3 flex gap-2 opacity-0 transition group-hover:opacity-100">
          <a
            href="#"
            aria-label={"#{@mentor.name} on X"}
            class="grid h-8 w-8 place-items-center rounded-full bg-white/20 text-white transition hover:bg-primary"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.24 2H21.5l-7.5 8.57L23 22h-6.9l-5.4-7.06L4.5 22H1.24l8.02-9.17L1 2h7.07l4.88 6.45z" />
            </svg>
          </a>
          <a
            href="#"
            aria-label={"#{@mentor.name} on Facebook"}
            class="grid h-8 w-8 place-items-center rounded-full bg-white/20 text-white transition hover:bg-primary"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
              <path d="M14 9h3l.5-3.5H14V3.7c0-1 .3-1.7 1.8-1.7H18V-.1C17.6-.2 16.4-.3 15-.3 12-.3 11 1.4 11 4.4v1.1H8V9h3v13h3z" />
            </svg>
          </a>
          <a
            href="#"
            aria-label={"#{@mentor.name} on LinkedIn"}
            class="grid h-8 w-8 place-items-center rounded-full bg-white/20 text-white transition hover:bg-primary"
          >
            <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
              <path d="M4.98 3.5A2.5 2.5 0 1 1 0 3.5a2.5 2.5 0 0 1 4.98 0zM.2 8h4.6v16H.2zm7.5 0H12v2.2h.07c.63-1.2 2.17-2.46 4.46-2.46C21.1 7.74 24 10 24 14.6V24h-4.8v-8c0-2-.04-4.5-2.75-4.5-2.75 0-3.17 2.15-3.17 4.36V24H8.5z" />
            </svg>
          </a>
        </div>
      </div>
    </div>
    """
  end

  def faqs(assigns) do
    ~H"""
    <section id="faqs" class="bg-slate-50 py-20 lg:py-28">
      <div class="mx-auto max-w-3xl px-5 lg:px-8">
        <h2 class="text-center text-3xl font-semibold text-dark sm:text-4xl">
          Frequently Asked Questions
        </h2>
        <p class="mx-auto mt-4 max-w-xl text-center text-body">
          Quick answers before you start learning.
        </p>
        <div class="mt-12 space-y-4">
          <.faq_item question="Can I learn at my own pace?">
            Yes. Lessons are self-paced — work through a course whenever suits you, and your
            progress is saved so you can pick up exactly where you left off.
          </.faq_item>
          <.faq_item question="Do courses include certificates?">
            Most courses include a certificate of completion, issued automatically once you finish
            the required lessons. You can download it from your dashboard at any time.
          </.faq_item>
          <.faq_item question="Can I learn on mobile?">
            Yes. Wasomi runs in your browser, so you can follow any course from a phone, tablet or
            laptop without installing an app.
          </.faq_item>
          <.faq_item question="How long do I have access to a course?">
            Once you enrol, the course stays available in your dashboard for as long as you need
            it — there's no expiry on completed enrolments.
          </.faq_item>
        </div>
      </div>
    </section>
    """
  end

  attr :question, :string, required: true
  slot :inner_block, required: true

  defp faq_item(assigns) do
    ~H"""
    <details class="group rounded-xl border border-black/10 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
      <summary class="flex cursor-pointer items-center justify-between gap-4 py-5 text-lg font-medium text-dark">
        {@question}
        <span class="grid h-6 w-6 shrink-0 place-items-center text-primary">
          <svg
            class="h-5 w-5 transition group-open:rotate-45"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
          >
            <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
          </svg>
        </span>
      </summary>
      <p class="pb-6 text-body group-open:animate-checklist-in">{render_slot(@inner_block)}</p>
    </details>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer class="bg-secondary pb-8 pt-16">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid gap-12 sm:grid-cols-2 lg:grid-cols-[1.3fr_1fr_1fr_1fr]">
          <div>
            <a href="/" class="inline-flex items-center">
              <img src="/images/logo-reversed.png" alt="Wasomi" class="h-8 w-auto" />
            </a>
            <p class="mt-5 max-w-xs text-white/60">
              Practical courses for identification, barcodes, data quality and traceability.
            </p>
            <div class="mt-6 flex gap-3">
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-white/15 text-white/60 transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.24 2H21.5l-7.5 8.57L23 22h-6.9l-5.4-7.06L4.5 22H1.24l8.02-9.17L1 2h7.07l4.88 6.45z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-white/15 text-white/60 transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M14 9h3l.5-3.5H14V3.7c0-1 .3-1.7 1.8-1.7H18V-.1C17.6-.2 16.4-.3 15-.3 12-.3 11 1.4 11 4.4v1.1H8V9h3v13h3z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-white/15 text-white/60 transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M4.98 3.5A2.5 2.5 0 1 1 0 3.5a2.5 2.5 0 0 1 4.98 0zM.2 8h4.6v16H.2zm7.5 0H12v2.2h.07c.63-1.2 2.17-2.46 4.46-2.46C21.1 7.74 24 10 24 14.6V24h-4.8v-8c0-2-.04-4.5-2.75-4.5-2.75 0-3.17 2.15-3.17 4.36V24H8.5z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-white/15 text-white/60 transition hover:border-primary hover:text-primary"
              >
                <svg
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                >
                  <rect x="2" y="2" width="20" height="20" rx="5.5" /><circle cx="12" cy="12" r="4.2" /><line
                    x1="17.5"
                    y1="6.5"
                    x2="17.5"
                    y2="6.5"
                  />
                </svg>
              </a>
            </div>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-white">
              Build Your <span class="text-primary">Skills</span>
            </h3>
            <p class="mt-2 text-sm text-white/50">
              Choose a course and learn each standard in order.
            </p>
            <ul class="mt-5 space-y-3 text-white/70">
              <li><a href="/courses" class="transition hover:text-primary">All courses</a></li>
              <li>
                <a href="#how-it-works" class="transition hover:text-primary">How it works</a>
              </li>
              <li><a href="#instructors" class="transition hover:text-primary">Instructors</a></li>
              <li>
                <a href="/certificates" class="transition hover:text-primary">Certificates</a>
              </li>
            </ul>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-white">
              Explore <span class="text-primary">GS1 Standards</span>
            </h3>
            <p class="mt-2 text-sm text-white/50">
              Find learning by the standard or business task you need.
            </p>
            <ul class="mt-5 space-y-3 text-white/70">
              <li><a href="/courses" class="transition hover:text-primary">Identification</a></li>
              <li>
                <a href="/courses" class="transition hover:text-primary">Barcodes and 2D codes</a>
              </li>
              <li><a href="/courses" class="transition hover:text-primary">Traceability</a></li>
              <li><a href="/courses" class="transition hover:text-primary">GS1 Digital Link</a></li>
            </ul>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-white">Support</h3>
            <p class="mt-2 text-sm text-white/50">
              Quick answers before you start learning.
            </p>
            <ul class="mt-5 space-y-3 text-white/70">
              <li><a href="#faqs" class="transition hover:text-primary">FAQs</a></li>
              <li>
                <a href="mailto:hello@wasomi.com" class="transition hover:text-primary">
                  Contact us
                </a>
              </li>
            </ul>
          </div>
        </div>
        <div class="mt-12 border-t border-white/10 pt-6">
          <div class="flex flex-col items-center justify-between gap-4 text-sm text-white/50 sm:flex-row">
            <p>© 2026 Wasomi. All rights reserved.</p>
            <div class="flex items-center gap-5">
              <a href="#" class="transition hover:text-primary">Privacy Policy</a>
              <a href="#" class="transition hover:text-primary">Terms &amp; Conditions</a>
            </div>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
