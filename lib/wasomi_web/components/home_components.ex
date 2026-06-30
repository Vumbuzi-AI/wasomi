defmodule WasomiWeb.HomeComponents do
  use Phoenix.Component
  use Gettext, backend: WasomiWeb.Gettext

  alias Wasomi.Catalog

  attr :current_user, :map, default: nil

  def home_header(assigns) do
    ~H"""
    <header class="absolute inset-x-0 top-0 z-50">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <nav class="flex items-center justify-between gap-4 py-6">
          <!-- logo -->
          <a href="/" class="flex items-center gap-2.5">
            <span class="grid h-9 w-9 place-items-center rounded-[10px] bg-primary">
              <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none">
                <path
                  d="M5 18V8l7 7 7-7v10"
                  stroke="#fff"
                  stroke-width="2.3"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </span>
            <span class="text-2xl font-bold text-dark">Wasomi</span>
          </a>
          
    <!-- mobile toggle (peer checkbox) -->
          <input type="checkbox" id="nav-toggle" class="peer hidden" />
          
    <!-- nav menu -->
          <div class="absolute left-4 right-4 top-20 hidden flex-col gap-1 rounded-2xl border border-black/5 bg-white p-4 shadow-xl peer-checked:flex lg:static lg:flex lg:flex-row lg:items-center lg:gap-8 lg:border-0 lg:bg-transparent lg:p-0 lg:shadow-none">
            <!-- dropdown: Home -->
            <div class="group relative">
              <button class="flex w-full items-center gap-1.5 py-2 font-medium text-dark transition hover:text-primary">
                Home
                <svg
                  class="h-4 w-4 transition group-hover:rotate-180 group-hover:text-primary"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>
              <div class="z-50 hidden min-w-[180px] flex-col rounded-xl bg-white p-2 lg:absolute lg:left-0 lg:top-full lg:border lg:border-black/5 lg:shadow-xl group-hover:flex group-focus-within:flex">
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Home 1
                </a>
                <a href="#" class="rounded-lg px-4 py-2 text-primary transition hover:bg-mint">
                  Home 2
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Home 3
                </a>
              </div>
            </div>
            <!-- dropdown: Pages -->
            <div class="group relative">
              <button class="flex w-full items-center gap-1.5 py-2 font-medium text-dark transition hover:text-primary">
                Pages
                <svg
                  class="h-4 w-4 transition group-hover:rotate-180 group-hover:text-primary"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <polyline points="6 9 12 15 18 9" />
                </svg>
              </button>
              <div class="z-50 hidden min-w-[200px] flex-col rounded-xl bg-white p-2 lg:absolute lg:left-0 lg:top-full lg:border lg:border-black/5 lg:shadow-xl group-hover:flex group-focus-within:flex">
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Contact Us
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Privacy Policy
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Terms &amp; Conditions
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Licenses
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Changelog
                </a>
                <a
                  href="#"
                  class="rounded-lg px-4 py-2 text-dark transition hover:bg-mint hover:text-primary"
                >
                  Style Guide
                </a>
              </div>
            </div>
            <a href="/courses" class="py-2 font-medium text-dark transition hover:text-primary">
              Courses
            </a>
            <a href="#mentors" class="py-2 font-medium text-dark transition hover:text-primary">
              Mentors
            </a>
            <a href="#blog" class="py-2 font-medium text-dark transition hover:text-primary">Blog</a>
            <a href="#" class="py-2 font-medium text-dark transition hover:text-primary">About Us</a>
          </div>
          
    <!-- right -->
          <div class="flex items-center gap-3">
            <a
              :if={@current_user}
              href={home_destination_path(@current_user)}
              class="group hidden items-center gap-2 rounded-full bg-dark py-1.5 pl-5 pr-1.5 font-medium text-white transition hover:bg-primary sm:inline-flex"
            >
              {home_destination_label(@current_user)}
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
            </a>
            <a
              :if={!@current_user}
              href="/users/log_in"
              class="group hidden items-center gap-2 rounded-full border border-dark py-1.5 pl-5 pr-1.5 font-medium text-dark transition hover:bg-dark hover:text-white sm:inline-flex"
            >
              Login
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
    </header>
    """
  end

  defp home_destination_path(%{role: :admin}), do: "/admin"
  defp home_destination_path(_user), do: "/dashboard"

  defp home_destination_label(%{role: :admin}), do: "Admin dashboard"
  defp home_destination_label(_user), do: "My dashboard"

  def hero(assigns) do
    ~H"""
    <section class="relative overflow-hidden bg-gradient-to-b from-mint via-white to-white pt-20 pb-20 ">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid items-center gap-12 lg:grid-cols-2">
          <div>
            <h1 class="text-4xl font-semibold leading-[1.1] text-dark sm:text-5xl lg:text-6xl">
              Best Courses to Expand Your Digital Abilities
            </h1>
            <p class="mt-6 max-w-xl text-lg text-body">
              Explore courses that expand your digital abilities, covering key areas like data analytics, design, and marketing for career growth and innovation.
            </p>
            <a
              href="/courses"
              class="group mt-8 inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              Explore Courses
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
                  <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
                </svg>
              </span>
            </a>
            <div class="mt-12">
              <p class="text-base font-medium text-dark">Over 5,000 Students Land Jobs</p>
              <div class="mt-4 flex flex-wrap items-center gap-x-8 gap-y-4 opacity-70">
                <span class="flex items-center gap-2 text-lg font-semibold text-muted">
                  <svg
                    class="h-7 w-7"
                    viewBox="0 0 32 32"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linejoin="round"
                  ><path d="M16 6l11 19H5z" /></svg>Vertex
                </span>
                <span class="flex items-center gap-2 text-lg font-semibold text-muted">
                  <svg
                    class="h-7 w-7"
                    viewBox="0 0 32 32"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                  ><circle cx="16" cy="16" r="11" /></svg>Lumio
                </span>
                <span class="flex items-center gap-2 text-lg font-semibold text-muted">
                  <svg
                    class="h-7 w-7"
                    viewBox="0 0 32 32"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                  ><rect x="6" y="6" width="20" height="20" rx="5" /></svg>Nimbus
                </span>
                <span class="flex items-center gap-2 text-lg font-semibold text-muted">
                  <svg
                    class="h-7 w-7"
                    viewBox="0 0 32 32"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linejoin="round"
                  ><path d="M16 5l11 11-11 11L5 16z" /></svg>Apex
                </span>
                <span class="flex items-center gap-2 text-lg font-semibold text-muted">
                  <svg
                    class="h-7 w-7"
                    viewBox="0 0 32 32"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linejoin="round"
                  ><path d="M16 5l10 6v12l-10 6-10-6V11z" /></svg>Stellar
                </span>
              </div>
            </div>
          </div>

          <div class="relative px-4 pt-2 sm:px-6">
            
    <!-- white photo card -->
            <div class="relative mt-4">
              <img
                src="/images/hero_image.jpg"
                alt="Man working with laptop"
                class="aspect-[4/5] w-full rounded-[20px] object-cover"
              />
            </div>
            <!-- rotating "learn digital abilities" badge -->
            <div class="absolute -bottom-6 -left-6 z-20 grid h-36 w-36 place-items-center rounded-full bg-[#f97316] text-white shadow-xl">
              <svg
                class="absolute inset-0 h-full w-full animate-[spin_16s_linear_infinite]"
                viewBox="0 0 100 100"
              >
                <defs>
                  <path id="hero-badge-arc" d="M50,50 m-38,0 a38,38 0 1,1 76,0 a38,38 0 1,1 -76,0" />
                </defs>
                <text class="fill-white text-[10px] font-semibold uppercase tracking-[0.24em]">
                  <textPath href="#hero-badge-arc" startOffset="0%">
                    • Learn Skills Online • Wasomi
                  </textPath>
                </text>
              </svg>
              <svg class="h-12 w-12" viewBox="0 0 24 24" fill="currentColor">
                <path d="M12 0c1 7.4 4.6 11 12 12-7.4 1-11 4.6-12 12-1-7.4-4.6-11-12-12 7.4-1 11-4.6 12-12Z" />
              </svg>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :courses, :list, default: []

  def top_courses_section(assigns) do
    ~H"""
    <section id="courses" class="bg-soft py-8">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <h2 class="mx-auto max-w-2xl text-center text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
          Our Platform’s Top Courses Chosen Just for You
        </h2>

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

  attr :course, :map, required: true
  attr :image_class, :string, default: "h-56"

  def course_card(assigns) do
    ~H"""
    <a
      href={"/courses/#{@course.slug}"}
      class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
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
          <div class="text-lg font-semibold text-dark">
            {Catalog.format_price(@course)}
          </div>
        </div>
        <h3 class="mt-4 text-lg font-medium text-dark">{@course.title}</h3>
        <p class="mt-3 line-clamp-2 text-sm leading-6 text-body">{@course.subtitle}</p>
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

  def why_choose_us(assigns) do
    ~H"""
    <section class="py-12">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid items-center gap-12 lg:grid-cols-2">
          <div class="relative">
            <img
              src="https://images.unsplash.com/photo-1531482615713-2afd69097998?auto=format&fit=crop&w=1100&q=80"
              alt="Man working with laptop"
              class="aspect-square w-full rounded-[28px] object-cover"
            />
            <div class="absolute bottom-6 left-6 w-52 rounded-2xl bg-white p-5 shadow-xl">
              <p class="text-sm text-body">Average Class Completion Rate</p>
              <div class="mt-2 flex items-center gap-2">
                <span class="flex items-center gap-1 rounded-full bg-mint px-2 py-0.5 text-sm font-medium text-primary">
                  <svg
                    class="h-4 w-4"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.5"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  ><polyline points="23 6 13.5 15.5 8.5 10.5 1 18" /><polyline points="17 6 23 6 23 12" /></svg>65+
                </span>
              </div>
              <p class="mt-3 text-4xl font-semibold text-dark">95%</p>
            </div>
          </div>
          <div>
            <h2 class="text-3xl font-semibold text-dark sm:text-4xl">
              Why Choose Us for Your Learning Journey
            </h2>
            <p class="mt-5 text-body">
              Choose us for expert-led digital skills development, tailored resources, and practical, real-world projects that empower your learning and career growth.
            </p>
            <div class="mt-8 grid gap-8 sm:grid-cols-2">
              <div>
                <p class="text-3xl font-semibold text-dark">100,000+</p>
                <p class="mt-2 text-body">
                  Students effectively enhanced digital skills using our platform.
                </p>
              </div>
              <div>
                <p class="text-3xl font-semibold text-dark">20,000+</p>
                <p class="mt-2 text-body">
                  Students have built successful careers in various tech companies.
                </p>
              </div>
            </div>
            <a
              href="#"
              class="group mt-8 inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
            >
              More About Us
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

  attr :courses, :list, default: []

  def popular_courses(assigns) do
    ~H"""
    <section class="bg-soft py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="flex flex-col items-start justify-between gap-6 sm:flex-row sm:items-end">
          <h2 class="max-w-xl text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
            Our Popular Courses
          </h2>
          <a
            href="/courses"
            class="group inline-flex items-center gap-2 rounded-full border border-dark py-1.5 pl-6 pr-1.5 font-medium text-dark transition hover:bg-dark hover:text-white"
          >
            View All Courses
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

        <div :if={@courses != []} class="mt-12 grid grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3">
          <.course_card :for={course <- @courses} course={course} image_class="h-52" />
        </div>

        <div
          :if={@courses == []}
          class="mx-auto mt-12 max-w-xl rounded-3xl border border-black/5 bg-white p-10 text-center"
        >
          <h3 class="text-xl font-semibold text-dark">No published courses yet.</h3>
          <p class="mt-2 text-body">Publish courses in the admin area and they will show here.</p>
        </div>
      </div>
    </section>
    """
  end

  def unused_static_popular_courses(assigns) do
    ~H"""
    <section class="bg-soft py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <h2 class="text-center text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
          Our Popular Courses
        </h2>

        <div class="mt-12">
          <!-- radio inputs drive the tabs -->
          <input type="radio" name="ct" id="ct-a" class="peer/a sr-only" checked />
          <input type="radio" name="ct" id="ct-b" class="peer/b sr-only" />
          <input type="radio" name="ct" id="ct-c" class="peer/c sr-only" />
          <input type="radio" name="ct" id="ct-d" class="peer/d sr-only" />
          <input type="radio" name="ct" id="ct-e" class="peer/e sr-only" />
          <input type="radio" name="ct" id="ct-f" class="peer/f sr-only" />
          
    <!-- tab labels -->
          <div class="flex flex-wrap justify-center gap-3">
            <label
              for="ct-a"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/a:border-primary peer-checked/a:bg-primary peer-checked/a:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              ><rect x="3" y="3" width="7" height="7" rx="1" /><rect
                  x="14"
                  y="3"
                  width="7"
                  height="7"
                  rx="1"
                /><rect x="14" y="14" width="7" height="7" rx="1" /><rect
                  x="3"
                  y="14"
                  width="7"
                  height="7"
                  rx="1"
                /></svg>All Categories
            </label>
            <label
              for="ct-b"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/b:border-primary peer-checked/b:bg-primary peer-checked/b:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              ><polyline points="16 18 22 12 16 6" /><polyline points="8 6 2 12 8 18" /></svg>Development
            </label>
            <label
              for="ct-c"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/c:border-primary peer-checked/c:bg-primary peer-checked/c:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              ><path d="M12 19l7-7 3 3-7 7-3-3z" /><path d="M18 13l-1.5-7.5L2 2l3.5 14.5L13 18z" /><circle
                  cx="11"
                  cy="11"
                  r="2"
                /></svg>UI/UX Design
            </label>
            <label
              for="ct-d"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/d:border-primary peer-checked/d:bg-primary peer-checked/d:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              ><rect x="3" y="3" width="18" height="18" rx="2" /><line x1="9" y1="3" x2="9" y2="21" /><line
                  x1="15"
                  y1="3"
                  x2="15"
                  y2="21"
                /></svg>Project Management
            </label>
            <label
              for="ct-e"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/e:border-primary peer-checked/e:bg-primary peer-checked/e:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              ><rect x="4" y="2" width="16" height="20" rx="2" /><line x1="8" y1="6" x2="16" y2="6" /><line
                  x1="16"
                  y1="14"
                  x2="16"
                  y2="18"
                /><line x1="8" y1="18" x2="12" y2="18" /></svg>Accounting
            </label>
            <label
              for="ct-f"
              class="flex cursor-pointer items-center gap-2 rounded-full border border-black/10 bg-white px-5 py-2.5 text-sm font-medium text-dark transition hover:border-primary peer-checked/f:border-primary peer-checked/f:bg-primary peer-checked/f:text-white"
            >
              <svg
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              ><path d="M3 11l16-5v12L3 14z" /><path d="M11.5 16.8a3 3 0 0 1-5.7-1.4" /></svg>Marketing
            </label>
          </div>
          
    <!-- panes -->
        <!-- A: all -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/a:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1561070791-2526d30994b5?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">UI/UX Essentials for Engaging</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>6 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $119<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Cloud Computing Introduction</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>5 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Data Analytics Fundamentals</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>4 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1545235617-9465d2a55698?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    UI/UX Design
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $122<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Email Marketing Techniques</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>3 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $212<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Financial Accounting Essentials</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>5 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1432888622747-4eb9a8efeb07?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    UI/UX Design
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $110<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">SEO Fundamentals</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>4 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
          
    <!-- B: development -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/b:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1542831371-29b0f74f9713?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Development
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $220<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">HTML, CSS, and JavaScript</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>4h 32min
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
          
    <!-- C: ui/ux -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/c:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1561070791-2526d30994b5?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">UI/UX Essentials for Engaging</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>6 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $119<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Cloud Computing Introduction</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>5 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Data Analytics Fundamentals</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>4 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
          
    <!-- D: project mgmt -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/d:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1561070791-2526d30994b5?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Project Management
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $150<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">
                  UX Research &amp; Usability Testing
                </h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>3h 50min
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
          
    <!-- E: accounting -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/e:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1451187580459-43490279c0fa?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $119<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Cloud Computing Introduction</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>5 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $212<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Financial Accounting Essentials</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>5 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1552664730-d307ca884978?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Accounting
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $110<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Stakeholders Management</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>2hr 35min
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
          
    <!-- F: marketing -->
          <div class="mt-12 hidden grid-cols-1 gap-7 sm:grid-cols-2 lg:grid-cols-3 peer-checked/f:grid">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1561070791-2526d30994b5?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">UI/UX Essentials for Engaging</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>6 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $221<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Data Analytics Fundamentals</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>4 weeks
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=900&q=80"
                  alt=""
                  class="h-52 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-6">
                <div class="flex items-center justify-between">
                  <span class="rounded-full bg-mint px-3 py-1 text-sm font-medium text-primary">
                    Marketing
                  </span>
                  <div class="text-xl font-semibold text-dark">
                    $210<span class="text-base text-body">.00</span>
                  </div>
                </div>
                <h3 class="mt-4 text-lg font-medium text-dark">Google Ads &amp; PPC Campaigns</h3>
                <div class="mt-5 flex items-center gap-5 text-sm text-body">
                  <span class="flex items-center gap-2">
                    <svg
                      class="h-5 w-5 text-muted"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><circle cx="12" cy="12" r="9" /><polyline points="12 7 12 12 15 14" /></svg>2h 23min
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
                    ><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><polyline points="14 3 14 8 19 8" /></svg>30 lectures
                  </span>
                </div>
              </div>
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def digital_skills(assigns) do
    ~H"""
    <section class="py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid gap-12 lg:grid-cols-2">
          <div>
            <h2 class="text-3xl font-semibold text-dark sm:text-4xl">
              Unlock New Potential with Digital Skills Mastery
            </h2>
            <p class="mt-5 text-body">
              Unlock potential, stand out professionally, and drive impactful results with advanced mastery of digital skills.
            </p>
            <div class="mt-10 space-y-6">
              <div class="flex gap-5">
                <span class="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-mint text-primary">
                  <svg
                    class="h-6 w-6"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle
                      cx="12"
                      cy="7"
                      r="4"
                    />
                  </svg>
                </span>
                <div>
                  <h3 class="text-lg font-medium text-dark">Sign up and get started</h3>
                  <p class="mt-1 text-body">Create your account, and start learning instantly.</p>
                </div>
              </div>
              <div class="flex gap-5">
                <span class="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-secondary/10 text-secondary">
                  <svg
                    class="h-6 w-6"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M22 10L12 5 2 10l10 5 10-5z" /><path d="M6 12v5c0 1.5 2.7 3 6 3s6-1.5 6-3v-5" />
                  </svg>
                </span>
                <div>
                  <h3 class="text-lg font-medium text-dark">Explore courses tailored to you</h3>
                  <p class="mt-1 text-body">Browse a range of courses across various fields.</p>
                </div>
              </div>
              <div class="flex gap-5">
                <span class="grid h-14 w-14 shrink-0 place-items-center rounded-2xl bg-amber-100 text-amber-600">
                  <svg
                    class="h-6 w-6"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" /><polyline points="17 6 23 6 23 12" />
                  </svg>
                </span>
                <div>
                  <h3 class="text-lg font-medium text-dark">Keep learning and growing</h3>
                  <p class="mt-1 text-body">Continue exploring and advancing your skills!</p>
                </div>
              </div>
            </div>
          </div>
          <div>
            <div class="relative overflow-hidden rounded-3xl">
              <img
                src="https://images.unsplash.com/photo-1531482615713-2afd69097998?auto=format&fit=crop&w=1100&q=80"
                alt=""
                class="h-72 w-full object-cover"
              />
              <span class="absolute inset-0 grid place-items-center bg-black/20">
                <span class="grid h-16 w-16 place-items-center rounded-full bg-white text-primary shadow-lg">
                  <svg class="h-6 w-6" viewBox="0 0 24 24" fill="currentColor">
                    <polygon points="7 4 20 12 7 20 7 4" />
                  </svg>
                </span>
              </span>
            </div>
            <div class="mt-6">
              <h3 class="text-xl font-semibold text-dark">More than 300+ Courses for You</h3>
              <p class="mt-2 text-body">
                Access a diverse selection of 500+ courses, built to deepen your skills, broaden your insights, and fast-track your career.
              </p>
            </div>
            <div class="mt-6 grid grid-cols-3 gap-4">
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1554224154-26032ffc0d07?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1517245386807-bb43f82c33c4?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1611162617474-5b21e879e113?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1611926653458-09294b3142bf?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1517180102446-f3ece451e9d8?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
              <div class="overflow-hidden rounded-2xl">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=500&q=80"
                  alt=""
                  class="h-28 w-full object-cover"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

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

  def testimonials(assigns) do
    ~H"""
    <section class="py-20 lg:py-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <h2 class="text-center text-3xl font-semibold text-dark sm:text-4xl lg:text-5xl">
          Happy Students Say About Our Courses
        </h2>
        <div class="mt-14 grid gap-7 lg:grid-cols-3">
          <figure class="rounded-3xl border border-black/5 bg-soft p-8">
            <svg class="h-10 w-12 text-primary" viewBox="0 0 56 48" fill="currentColor">
              <path d="M0 48V27C0 12 9 2.5 24 0l2.5 6.5C17.5 9 13 14.5 13 21h11v27H0zm32 0V27C32 12 41 2.5 56 0l2.5 6.5C49.5 9 45 14.5 45 21h11v27H32z" />
            </svg>
            <blockquote class="mt-6 text-lg text-dark">
              This platform transformed my skills! Engaging courses, well-structured, with knowledgeable instructors who simplify complex topics. Covers essentials—highly recommended for growth!
            </blockquote>
            <figcaption class="mt-6">
              <p class="text-lg font-medium text-dark">Samuel John</p>
              <p class="text-body">UI/UX Designer</p>
            </figcaption>
          </figure>
          <figure class="relative overflow-hidden rounded-3xl bg-dark p-8">
            <svg class="h-10 w-12 text-primary" viewBox="0 0 56 48" fill="currentColor">
              <path d="M0 48V27C0 12 9 2.5 24 0l2.5 6.5C17.5 9 13 14.5 13 21h11v27H0zm32 0V27C32 12 41 2.5 56 0l2.5 6.5C49.5 9 45 14.5 45 21h11v27H32z" />
            </svg>
            <blockquote class="mt-6 text-lg text-white">
              Exceptional platform for career growth! The up-to-date curriculum, skilled instructors, and hands-on exercises make learning impactful and rewarding.
            </blockquote>
            <figcaption class="mt-6 flex items-center justify-between">
              <div>
                <p class="text-lg font-medium text-white">Michael Anthony</p>
                <p class="text-white/60">Software Engineer</p>
              </div>
              <a href="#" class="grid h-12 w-12 place-items-center rounded-full bg-primary text-white">
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                  <polygon points="7 4 20 12 7 20 7 4" />
                </svg>
              </a>
            </figcaption>
          </figure>
          <figure class="rounded-3xl border border-black/5 bg-soft p-8">
            <svg class="h-10 w-12 text-primary" viewBox="0 0 56 48" fill="currentColor">
              <path d="M0 48V27C0 12 9 2.5 24 0l2.5 6.5C17.5 9 13 14.5 13 21h11v27H0zm32 0V27C32 12 41 2.5 56 0l2.5 6.5C49.5 9 45 14.5 45 21h11v27H32z" />
            </svg>
            <blockquote class="mt-6 text-lg text-dark">
              The courses are engaging, taught by knowledgeable instructors who break down complex topics with ease. Highly recommended for personal and professional growth!
            </blockquote>
            <figcaption class="mt-6">
              <p class="text-lg font-medium text-dark">Thomas Edward</p>
              <p class="text-body">Digital Marketer</p>
            </figcaption>
          </figure>
        </div>
      </div>
    </section>
    """
  end

  def faqs(assigns) do
    ~H"""
    <section class="bg-soft py-20 lg:py-28">
      <div class="mx-auto max-w-3xl px-5 lg:px-8">
        <h2 class="text-center text-3xl font-semibold text-dark sm:text-4xl">
          Frequently Asked Questions
        </h2>
        <p class="mx-auto mt-4 max-w-xl text-center text-body">
          Frequently Asked Questions offers quick answers to common queries, guiding users through features and functionalities effortlessly.
        </p>
        <div class="mt-12 space-y-4">
          <details class="group rounded-2xl border border-black/5 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
            <summary class="flex cursor-pointer items-center justify-between py-5 text-lg font-medium text-dark">
              Can I Track My Assignments and Grades?<span class="ml-4 grid h-6 w-6 shrink-0 place-items-center text-primary"><svg
                  class="h-5 w-5 transition group-open:rotate-45"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                ><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg></span>
            </summary>
            <p class="pb-6 text-body">
              Yes, you can try us for free for 30 days. If you want, we’ll provide you with a free, personalized 30-minute onboarding call to get you up and running as soon as possible.
            </p>
          </details>
          <details class="group rounded-2xl border border-black/5 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
            <summary class="flex cursor-pointer items-center justify-between py-5 text-lg font-medium text-dark">
              Does the LMS support video lessons and live classes?<span class="ml-4 grid h-6 w-6 shrink-0 place-items-center text-primary"><svg
                  class="h-5 w-5 transition group-open:rotate-45"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                ><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg></span>
            </summary>
            <p class="pb-6 text-body">
              Yes, you can try us for free for 30 days. If you want, we’ll provide you with a free, personalized 30-minute onboarding call to get you up and running as soon as possible.
            </p>
          </details>
          <details class="group rounded-2xl border border-black/5 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
            <summary class="flex cursor-pointer items-center justify-between py-5 text-lg font-medium text-dark">
              How can I communicate with my instructor?<span class="ml-4 grid h-6 w-6 shrink-0 place-items-center text-primary"><svg
                  class="h-5 w-5 transition group-open:rotate-45"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                ><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg></span>
            </summary>
            <p class="pb-6 text-body">
              Yes, you can try us for free for 30 days. If you want, we’ll provide you with a free, personalized 30-minute onboarding call to get you up and running as soon as possible.
            </p>
          </details>
          <details class="group rounded-2xl border border-black/5 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
            <summary class="flex cursor-pointer items-center justify-between py-5 text-lg font-medium text-dark">
              What support is available for students and instructors?<span class="ml-4 grid h-6 w-6 shrink-0 place-items-center text-primary"><svg
                  class="h-5 w-5 transition group-open:rotate-45"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                ><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg></span>
            </summary>
            <p class="pb-6 text-body">
              Yes, you can try us for free for 30 days. If you want, we’ll provide you with a free, personalized 30-minute onboarding call to get you up and running as soon as possible.
            </p>
          </details>
          <details class="group rounded-2xl border border-black/5 bg-white px-6 [&_summary::-webkit-details-marker]:hidden">
            <summary class="flex cursor-pointer items-center justify-between py-5 text-lg font-medium text-dark">
              Are there interactive features for students?<span class="ml-4 grid h-6 w-6 shrink-0 place-items-center text-primary"><svg
                  class="h-5 w-5 transition group-open:rotate-45"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                ><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg></span>
            </summary>
            <p class="pb-6 text-body">
              Yes, you can try us for free for 30 days. If you want, we’ll provide you with a free, personalized 30-minute onboarding call to get you up and running as soon as possible.
            </p>
          </details>
        </div>
      </div>
    </section>
    """
  end

  def blog(assigns) do
    ~H"""
    <section id="blog" class="py-8">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="flex flex-col items-start justify-between gap-6 sm:flex-row sm:items-end">
          <h2 class="max-w-xl text-3xl font-semibold text-dark sm:text-4xl">
            Empower Your Journey with Expert Career Insights
          </h2>
          <a
            href="#"
            class="group inline-flex items-center gap-2 rounded-full bg-dark py-1.5 pl-6 pr-1.5 font-medium text-white transition hover:bg-primary"
          >
            View All Blogs
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
                <line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" />
              </svg>
            </span>
          </a>
        </div>
        <div class="mt-14 grid gap-7 lg:grid-cols-2">
          <!-- feature -->
          <a
            href="#"
            class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
          >
            <div class="overflow-hidden">
              <img
                loading="lazy"
                src="https://images.unsplash.com/photo-1557804506-669a67965ba0?auto=format&fit=crop&w=1100&q=80"
                alt=""
                class="h-72 w-full object-cover transition duration-500 group-hover:scale-105"
              />
            </div>
            <div class="p-7">
              <div class="flex items-center gap-2 text-sm text-body">
                <span class="font-medium text-dark">William Henry</span><span>•</span><span>15 min</span>
              </div>
              <h3 class="mt-3 text-2xl font-semibold text-dark">
                Top Marketing Skills to Boost Your Brand Engagement and Reach
              </h3>
              <p class="mt-3 text-body">
                Learn essential security practices to protect your CMS from threats.
              </p>
            </div>
          </a>
          <!-- small cards -->
          <div class="grid gap-6 sm:grid-cols-2">
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1521737711867-e3b97375f902?auto=format&fit=crop&w=600&q=80"
                  alt=""
                  class="h-40 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-5">
                <div class="flex items-center gap-2 text-sm text-body">
                  <span class="font-medium text-dark">Ethan Samuel</span><span>•</span><span>06 min</span>
                </div>
                <h3 class="mt-2 font-semibold text-dark">
                  5 High-Impact Communication Skills for Every Professional
                </h3>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1486312338219-ce68d2c6f44d?auto=format&fit=crop&w=600&q=80"
                  alt=""
                  class="h-40 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-5">
                <div class="flex items-center gap-2 text-sm text-body">
                  <span class="font-medium text-dark">Robert David</span><span>•</span><span>08 min</span>
                </div>
                <h3 class="mt-2 font-semibold text-dark">
                  Building a LinkedIn Profile That Attracts Opportunities
                </h3>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1543269865-cbf427effbad?auto=format&fit=crop&w=600&q=80"
                  alt=""
                  class="h-40 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-5">
                <div class="flex items-center gap-2 text-sm text-body">
                  <span class="font-medium text-dark">Alexander Paul</span><span>•</span><span>09 min</span>
                </div>
                <h3 class="mt-2 font-semibold text-dark">
                  Effective Networking Strategies to Boost Career Success
                </h3>
              </div>
            </a>
            <a
              href="#"
              class="group block overflow-hidden rounded-3xl border border-black/5 bg-white transition hover:shadow-xl"
            >
              <div class="overflow-hidden">
                <img
                  loading="lazy"
                  src="https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?auto=format&fit=crop&w=600&q=80"
                  alt=""
                  class="h-40 w-full object-cover transition duration-500 group-hover:scale-105"
                />
              </div>
              <div class="p-5">
                <div class="flex items-center gap-2 text-sm text-body">
                  <span class="font-medium text-dark">Ethan Samuel</span><span>•</span><span>10 min</span>
                </div>
                <h3 class="mt-2 font-semibold text-dark">
                  Top Accounting Skills for a Data-Driven World
                </h3>
              </div>
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def cta(assigns) do
    ~H"""
    <section class="pb-20 lg:pb-28">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="relative overflow-hidden rounded-[32px] bg-gradient-to-r from-indigo-600 via-primary to-secondary px-6 py-16 text-center sm:px-12 lg:py-20">
          <h2 class="mx-auto max-w-3xl text-3xl font-semibold text-white sm:text-4xl">
            Join Driven Professionals &amp; Launch Your Dream Career Today!
          </h2>
          <p class="mx-auto mt-4 max-w-2xl text-white/80">
            Connect with a network of driven professionals, gain valuable insights, and access resources that propel you toward your dream career.
          </p>
          <form
            class="mx-auto mt-8 flex max-w-lg items-center gap-2 rounded-full bg-white p-2"
            onsubmit="return false"
          >
            <input
              type="email"
              required
              placeholder="Enter your email"
              class="w-full rounded-full bg-transparent px-5 py-2.5 text-dark outline-none placeholder:text-body"
            />
            <button class="group inline-flex shrink-0 items-center gap-2 rounded-full bg-dark py-1.5 pl-5 pr-1.5 font-medium text-white transition hover:bg-primary">
              Join with Us<span class="grid h-9 w-9 place-items-center rounded-full bg-primary text-white transition group-hover:bg-dark"><svg
                  class="h-4 w-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                ><line x1="7" y1="17" x2="17" y2="7" /><polyline points="7 7 17 7 17 17" /></svg></span>
            </button>
          </form>
        </div>
      </div>
    </section>
    """
  end

  def footer(assigns) do
    ~H"""
    <footer class="border-t border-black/5 pt-16 pb-8">
      <div class="mx-auto max-w-container px-5 lg:px-8">
        <div class="grid gap-12 lg:grid-cols-[1.3fr_1fr_1fr_1.2fr]">
          <div>
            <a href="#" class="flex items-center gap-2.5">
              <span class="grid h-9 w-9 place-items-center rounded-[10px] bg-primary">
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none">
                  <path
                    d="M5 18V8l7 7 7-7v10"
                    stroke="#fff"
                    stroke-width="2.3"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  />
                </svg>
              </span>
              <span class="text-2xl font-bold text-dark">Wasomi</span>
            </a>
            <p class="mt-5 max-w-xs text-body">Unlock knowledge with expert-led online courses.</p>
            <div class="mt-6 flex gap-3">
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-black/10 text-muted transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.24 2H21.5l-7.5 8.57L23 22h-6.9l-5.4-7.06L4.5 22H1.24l8.02-9.17L1 2h7.07l4.88 6.45z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-black/10 text-muted transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M14 9h3l.5-3.5H14V3.7c0-1 .3-1.7 1.8-1.7H18V-.1C17.6-.2 16.4-.3 15-.3 12-.3 11 1.4 11 4.4v1.1H8V9h3v13h3z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-black/10 text-muted transition hover:border-primary hover:text-primary"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M4.98 3.5A2.5 2.5 0 1 1 0 3.5a2.5 2.5 0 0 1 4.98 0zM.2 8h4.6v16H.2zm7.5 0H12v2.2h.07c.63-1.2 2.17-2.46 4.46-2.46C21.1 7.74 24 10 24 14.6V24h-4.8v-8c0-2-.04-4.5-2.75-4.5-2.75 0-3.17 2.15-3.17 4.36V24H8.5z" />
                </svg>
              </a>
              <a
                href="#"
                class="grid h-10 w-10 place-items-center rounded-full border border-black/10 text-muted transition hover:border-primary hover:text-primary"
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
            <h3 class="text-lg font-semibold text-dark">About Us</h3>
            <ul class="mt-5 space-y-3 text-body">
              <li><a href="#" class="transition hover:text-primary">Home 1</a></li>
              <li><a href="#" class="transition hover:text-primary">Home 2</a></li>
              <li><a href="#" class="transition hover:text-primary">Home 3</a></li>
              <li><a href="#" class="transition hover:text-primary">About Us</a></li>
              <li><a href="#courses" class="transition hover:text-primary">Courses</a></li>
            </ul>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-dark">Others</h3>
            <ul class="mt-5 space-y-3 text-body">
              <li><a href="#mentors" class="transition hover:text-primary">Mentors</a></li>
              <li><a href="#" class="transition hover:text-primary">Contact Us</a></li>
              <li><a href="#blog" class="transition hover:text-primary">Blog</a></li>
              <li><a href="#" class="transition hover:text-primary">Privacy Policy</a></li>
              <li><a href="#" class="transition hover:text-primary">Licenses</a></li>
            </ul>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-dark">Contact Us</h3>
            <ul class="mt-5 space-y-4 text-body">
              <li>
                <a href="tel:1234567890" class="flex items-center gap-3 transition hover:text-primary">
                  <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary"><svg
                      class="h-4 w-4"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3 19.5 19.5 0 0 1-6-6 19.8 19.8 0 0 1-3-8.6A2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7 13 13 0 0 0 .7 2.8 2 2 0 0 1-.5 2.1L8.1 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4 13 13 0 0 0 2.8.7 2 2 0 0 1 1.7 2z" /></svg></span>+123 456 7890
                </a>
              </li>
              <li>
                <a
                  href="mailto:hello@designmonks.com"
                  class="flex items-center gap-3 transition hover:text-primary"
                >
                  <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary"><svg
                      class="h-4 w-4"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><rect x="2" y="4" width="20" height="16" rx="2" /><polyline points="2 6 12 13 22 6" /></svg></span>hello@designmonks.com
                </a>
              </li>
              <li>
                <a href="#" class="flex items-start gap-3 transition hover:text-primary">
                  <span class="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-mint text-primary"><svg
                      class="h-4 w-4"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    ><path d="M21 10c0 6-9 12-9 12s-9-6-9-12a9 9 0 0 1 18 0z" /><circle
                      cx="12"
                      cy="10"
                      r="3"
                    /></svg></span>4886 Stroman Drives, California, South Stanton, USA
                </a>
              </li>
            </ul>
          </div>
        </div>
        <div class="mt-12 border-t border-black/5 pt-6">
          <div class="flex flex-col items-center justify-between gap-4 text-sm text-body sm:flex-row">
            <p>
              2025 © <a href="#" class="font-medium text-dark hover:text-primary">Design Monks</a>. All rights reserved.
            </p>
            <div class="flex items-center gap-3">
              <span>Payments:</span>
              <span class="rounded-md bg-[#1a1f71] px-2.5 py-1 text-xs font-bold text-white">
                VISA
              </span>
              <span class="rounded-md bg-[#eb001b] px-2.5 py-1 text-xs font-bold text-white">MC</span>
              <span class="rounded-md border border-black/10 bg-white px-2.5 py-1 text-xs font-bold text-[#003087]">
                PayPal
              </span>
              <span class="rounded-md bg-[#2e77bb] px-2.5 py-1 text-xs font-bold text-white">
                AMEX
              </span>
            </div>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
