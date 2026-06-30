# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Wasomi.Repo.insert!(%Wasomi.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ecto.Changeset
alias Wasomi.Accounts
alias Wasomi.Accounts.User
alias Wasomi.Catalog.{Course, CourseModule, Lecture}
alias Wasomi.Enrollments.Enrollment
alias Wasomi.Payments.Payment
alias Wasomi.Repo

admin_attrs = %{
  name: "Wasomi Admin",
  email: "admin@wasomi.test",
  phone: "254700000001",
  password: "password12345"
}

student_attrs = %{
  name: "One Student",
  email: "student@wasomi.test",
  phone: "254700000002",
  password: "student12345"
}

courses = [
  %{
    attrs: %{
      slug: "the-human-stack",
      title: "The Human Stack by Alvas",
      subtitle: "Communication and presentation skills for technology professionals",
      description:
        "Turn complex technical thinking into clear messages, persuasive presentations, and productive workplace conversations.",
      thumbnail_key: "/images/human-stack-course.svg",
      price_minor: 1_500_000,
      currency: "KES",
      status: :published,
      position: 1
    },
    modules: [
      {"Communication as a Technical Superpower",
       "Build the foundations for clear, intentional communication in technical environments.",
       [
         {"Why the human stack matters", 540},
         {"Diagnosing communication breakdowns", 660},
         {"Clarity, context, and intent", 720}
       ]},
      {"Know Your Audience and Message",
       "Shape a message around what your audience needs to understand, decide, or do.",
       [
         {"Reading the room", 600},
         {"From information to outcome", 780},
         {"The one-sentence message", 660}
       ]},
      {"Technical Storytelling",
       "Organise complex ideas into memorable narratives without losing accuracy.",
       [
         {"Story structure for technical ideas", 840},
         {"Explaining complexity with analogy", 720},
         {"Making evidence persuasive", 780}
       ]},
      {"Designing Clear Presentations",
       "Create slides and demonstrations that support your message instead of competing with it.",
       [
         {"One idea per slide", 720},
         {"Visual hierarchy and data", 840},
         {"Designing a coherent deck", 900}
       ]},
      {"Delivery and Executive Presence",
       "Develop a grounded delivery style for rooms, calls, demos, and recorded updates.",
       [
         {"Voice, pace, and pause", 660},
         {"Body language and virtual presence", 720},
         {"Handling tough questions", 900}
       ]},
      {"High-Stakes Workplace Communication",
       "Apply the human stack to feedback, difficult conversations, executive updates, and Q&A.",
       [
         {"Giving and receiving feedback", 840},
         {"Handling difficult conversations", 900},
         {"Executive updates and tough questions", 900}
       ]}
    ]
  },
  %{
    attrs: %{
      slug: "practical-data-analytics",
      title: "Practical Data Analytics",
      subtitle: "Use spreadsheets, SQL, and dashboards to turn raw data into decisions",
      description:
        "Learn the everyday analytics workflow: clean data, ask sharper questions, query datasets, and present reliable insights.",
      thumbnail_key:
        "https://images.unsplash.com/photo-1551288049-bebda4e38f71?auto=format&fit=crop&w=900&q=80",
      price_minor: 1_850_000,
      currency: "KES",
      status: :published,
      position: 2
    },
    modules: [
      {"Analytics Foundations", "Frame business questions and prepare trustworthy datasets.",
       [
         {"From question to metric", 720},
         {"Cleaning messy data", 840},
         {"Choosing useful visualisations", 780}
       ]},
      {"SQL for Analysis", "Query relational data and combine tables confidently.",
       [
         {"Filtering and grouping", 900},
         {"Joins without confusion", 960},
         {"Building repeatable reports", 840}
       ]},
      {"Dashboards and Decisions", "Package insights for teams and stakeholders.",
       [
         {"Designing decision dashboards", 780},
         {"Telling the story in the numbers", 720},
         {"Presenting recommendations", 660}
       ]}
    ]
  },
  %{
    attrs: %{
      slug: "ux-product-design-lab",
      title: "UX Product Design Lab",
      subtitle: "Research, prototype, and test digital products people can actually use",
      description:
        "Move from user insight to polished product flows with practical research, wireframing, prototyping, and usability testing.",
      thumbnail_key:
        "https://images.unsplash.com/photo-1561070791-2526d30994b5?auto=format&fit=crop&w=900&q=80",
      price_minor: 1_600_000,
      currency: "KES",
      status: :published,
      position: 3
    },
    modules: [
      {"Research That Guides Design", "Understand users before committing to screens.",
       [
         {"Planning useful interviews", 720},
         {"Mapping jobs and pain points", 780},
         {"Turning notes into insights", 840}
       ]},
      {"Interaction and Interface Design",
       "Create clear flows, wireframes, and responsive interfaces.",
       [
         {"Flow mapping", 660},
         {"Wireframes that communicate", 780},
         {"Visual hierarchy basics", 720}
       ]},
      {"Testing and Iteration", "Validate your work and improve it with evidence.",
       [
         {"Usability test scripts", 720},
         {"Reading behaviour, not opinions", 780},
         {"Prioritising design fixes", 660}
       ]}
    ]
  },
  %{
    attrs: %{
      slug: "digital-marketing-growth",
      title: "Digital Marketing Growth",
      subtitle: "Build campaigns across content, email, search, and paid channels",
      description:
        "Create a practical growth engine with positioning, content planning, conversion funnels, email campaigns, and performance reporting.",
      thumbnail_key:
        "https://images.unsplash.com/photo-1460925895917-afdab827c52f?auto=format&fit=crop&w=900&q=80",
      price_minor: 1_350_000,
      currency: "KES",
      status: :published,
      position: 4
    },
    modules: [
      {"Positioning and Content", "Clarify the audience, message, and channels for a campaign.",
       [
         {"Audience and offer fit", 660},
         {"Content pillars", 720},
         {"Campaign calendars", 780}
       ]},
      {"Funnels and Email", "Turn attention into leads and customers.",
       [
         {"Landing page anatomy", 780},
         {"Email sequences", 840},
         {"Conversion checkpoints", 720}
       ]},
      {"Performance Marketing", "Measure, optimise, and report campaign results.",
       [
         {"Channel metrics", 720},
         {"Simple paid campaign setup", 840},
         {"Reporting what matters", 660}
       ]}
    ]
  },
  %{
    attrs: %{
      slug: "project-management-for-digital-teams",
      title: "Project Management for Digital Teams",
      subtitle: "Plan, ship, and communicate digital work without losing momentum",
      description:
        "Learn lightweight project management methods for software, design, marketing, and operations teams.",
      thumbnail_key:
        "https://images.unsplash.com/photo-1552664730-d307ca884978?auto=format&fit=crop&w=900&q=80",
      price_minor: 1_400_000,
      currency: "KES",
      status: :published,
      position: 5
    },
    modules: [
      {"Planning the Work", "Define scope, outcomes, risks, and delivery rhythm.",
       [
         {"From brief to backlog", 720},
         {"Estimating with uncertainty", 780},
         {"Planning useful milestones", 660}
       ]},
      {"Running the Team", "Keep people aligned through rituals and clear communication.",
       [
         {"Standups and async updates", 660},
         {"Decision logs", 720},
         {"Stakeholder check-ins", 780}
       ]},
      {"Shipping and Learning", "Close projects cleanly and improve the next one.",
       [
         {"Launch readiness", 720},
         {"Post-launch retrospectives", 660},
         {"Turning lessons into process", 780}
       ]}
    ]
  },
  %{
    attrs: %{
      slug: "financial-skills-for-entrepreneurs",
      title: "Financial Skills for Entrepreneurs",
      subtitle: "Understand cash flow, pricing, budgets, and reports for better decisions",
      description:
        "Build the financial confidence to price offers, track cash, read reports, and make disciplined business decisions.",
      thumbnail_key:
        "https://images.unsplash.com/photo-1554224155-6726b3ff858f?auto=format&fit=crop&w=900&q=80",
      price_minor: 1_250_000,
      currency: "KES",
      status: :published,
      position: 6
    },
    modules: [
      {"Money Fundamentals", "Understand the numbers every founder should watch.",
       [
         {"Revenue, cost, and margin", 720},
         {"Cash flow basics", 780},
         {"Reading simple reports", 840}
       ]},
      {"Pricing and Planning", "Make pricing and budget choices with more confidence.",
       [
         {"Pricing models", 720},
         {"Budgeting for growth", 780},
         {"Scenario planning", 660}
       ]},
      {"Financial Discipline", "Build habits for sustainable business operations.",
       [
         {"Monthly review rhythms", 660},
         {"Managing receivables", 720},
         {"Decision rules for spending", 780}
       ]}
    ]
  }
]

# Ready-made public HLS streams so seeded lectures actually play in development.
# The Wasomi.Media.Demo adapter (config/dev.exs) streams these URLs directly.
demo_streams = [
  "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8",
  "https://test-streams.mux.dev/tos_ismc/main.m3u8",
  "https://stream.mux.com/VZtzUzGRv02OhRnZCxcNg49OilvolTqdnFLEqBsTwLx7g.m3u8"
]

Repo.transaction(fn ->
  confirmed_at = DateTime.utc_now() |> DateTime.truncate(:second)

  case Repo.get_by(User, email: admin_attrs.email) do
    nil ->
      {:ok, admin} = Accounts.register_user(admin_attrs)

      admin
      |> User.role_changeset(%{role: :admin})
      |> Changeset.put_change(:phone, admin_attrs.phone)
      |> Changeset.put_change(:confirmed_at, confirmed_at)
      |> Repo.update!()

    admin ->
      admin
      |> User.password_changeset(%{password: admin_attrs.password})
      |> Changeset.put_change(:name, admin_attrs.name)
      |> Changeset.put_change(:phone, admin_attrs.phone)
      |> Changeset.put_change(:role, :admin)
      |> Changeset.put_change(:confirmed_at, admin.confirmed_at || confirmed_at)
      |> Repo.update!()
  end

  student =
    case Repo.get_by(User, email: student_attrs.email) do
      nil ->
        {:ok, student} = Accounts.register_user(student_attrs)

        student
        |> User.role_changeset(%{role: :learner})
        |> Changeset.put_change(:phone, student_attrs.phone)
        |> Changeset.put_change(:confirmed_at, confirmed_at)
        |> Repo.update!()

      student ->
        student
        |> User.password_changeset(%{password: student_attrs.password})
        |> Changeset.put_change(:name, student_attrs.name)
        |> Changeset.put_change(:phone, student_attrs.phone)
        |> Changeset.put_change(:role, :learner)
        |> Changeset.put_change(:confirmed_at, student.confirmed_at || confirmed_at)
        |> Repo.update!()
    end

  seeded_courses =
    courses
    |> Enum.with_index()
    |> Enum.map(fn {%{attrs: course_attrs, modules: modules}, course_index} ->
      course =
        case Repo.get_by(Course, slug: course_attrs.slug) do
          nil ->
            %Course{}
            |> Course.changeset(course_attrs)
            |> Repo.insert!()

          course ->
            course
            |> Course.changeset(course_attrs)
            |> Repo.update!()
        end

      Enum.with_index(modules, 1)
      |> Enum.each(fn {{title, description, lectures}, module_position} ->
        course_module =
          case Repo.get_by(CourseModule, course_id: course.id, position: module_position) do
            nil -> %CourseModule{}
            existing -> existing
          end
          |> CourseModule.changeset(%{
            course_id: course.id,
            title: title,
            description: description,
            position: module_position
          })
          |> then(fn changeset ->
            if changeset.data.id, do: Repo.update!(changeset), else: Repo.insert!(changeset)
          end)

        Enum.with_index(lectures, 1)
        |> Enum.each(fn {{lecture_title, duration_seconds}, lecture_position} ->
          stream_index =
            rem(
              course_index * 9 + (module_position - 1) * 3 + (lecture_position - 1),
              length(demo_streams)
            )

          case Repo.get_by(Lecture, module_id: course_module.id, position: lecture_position) do
            nil -> %Lecture{}
            existing -> existing
          end
          |> Lecture.changeset(%{
            module_id: course_module.id,
            title: lecture_title,
            description: "A focused lesson with practical examples and an application exercise.",
            video_provider: :mux,
            video_asset_id: Enum.at(demo_streams, stream_index),
            duration_seconds: duration_seconds,
            position: lecture_position
          })
          |> then(fn changeset ->
            if changeset.data.id, do: Repo.update!(changeset), else: Repo.insert!(changeset)
          end)
        end)
      end)

      course
    end)

  course = List.first(seeded_courses)

  enrollment =
    case Repo.get_by(Enrollment, user_id: student.id, course_id: course.id) do
      nil -> %Enrollment{}
      existing -> existing
    end
    |> Enrollment.changeset(%{
      user_id: student.id,
      course_id: course.id,
      status: :active,
      enrolled_at: confirmed_at,
      activated_at: confirmed_at
    })
    |> then(fn changeset ->
      if changeset.data.id, do: Repo.update!(changeset), else: Repo.insert!(changeset)
    end)

  payment_attrs = %{
    user_id: student.id,
    course_id: course.id,
    enrollment_id: enrollment.id,
    provider: :paystack,
    provider_reference: "KBI-SEED-PAID-STUDENT-HUMAN-STACK",
    amount_minor: course.price_minor,
    currency: course.currency,
    status: :successful,
    paid_at: confirmed_at,
    raw_payload: %{
      "seeded" => true,
      "status" => "success",
      "reference" => "KBI-SEED-PAID-STUDENT-HUMAN-STACK"
    }
  }

  case Repo.get_by(Payment, provider_reference: payment_attrs.provider_reference) do
    nil -> %Payment{}
    existing -> existing
  end
  |> Payment.changeset(payment_attrs)
  |> then(fn changeset ->
    if changeset.data.id, do: Repo.update!(changeset), else: Repo.insert!(changeset)
  end)
end)

IO.puts("Seeded admin account: #{admin_attrs.email} / #{admin_attrs.password}")
IO.puts("Seeded paid student account: #{student_attrs.email} / #{student_attrs.password}")
IO.puts("Seeded #{length(courses)} published courses with modules and playable demo lectures.")
