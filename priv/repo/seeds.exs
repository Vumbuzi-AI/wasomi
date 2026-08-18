# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Deliberately minimal: one admin, one published course whose lectures carry
# every AI-generated artefact (transcript, open questions, lecture quiz,
# flashcards, practice set), and one learner enrolled in it. Enough to walk
# the whole admin *and* learner journey without waiting on any real
# generation job.

import Ecto.Query

alias Ecto.Changeset
alias Wasomi.Accounts
alias Wasomi.Accounts.User

alias Wasomi.Assessments.{
  Flashcard,
  FlashcardSet,
  LectureQuiz,
  LectureQuizQuestion,
  PracticeSet,
  PracticeSetQuestion,
  Question,
  Quiz
}

alias Wasomi.Catalog.{Course, CourseModule, Lecture, LectureQuestion, LectureTranscript}
alias Wasomi.Enrollments.Enrollment
alias Wasomi.Payments.Payment
alias Wasomi.Repo

defmodule Wasomi.Seeds.CloudflareVideo do
  alias Wasomi.Catalog.Lecture
  alias Wasomi.Media.Cloudflare

  @poll_interval_ms 3_000
  @max_poll_attempts 100

  def build_one_minute_video! do
    path = Path.join(System.tmp_dir!(), "wasomi-cloudflare-seed-60s.mp4")

    {output, status} =
      System.cmd(
        "ffmpeg",
        [
          "-y",
          "-f",
          "lavfi",
          "-i",
          "color=c=0x12372A:s=1280x720:d=60",
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=440:duration=60",
          "-shortest",
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-pix_fmt",
          "yuv420p",
          "-c:a",
          "aac",
          "-movflags",
          "+faststart",
          path
        ],
        stderr_to_stdout: true
      )

    if status != 0 do
      raise "Could not create the one-minute seed video with ffmpeg:\n#{output}"
    end

    path
  rescue
    error in ErlangError ->
      raise "Seeds require ffmpeg to create the one-minute Cloudflare video: #{Exception.message(error)}"
  end

  def ensure_uploaded!(
        %Lecture{video_provider: :cloudflare, video_asset_id: asset_id} = lecture,
        path
      )
      when is_binary(asset_id) and asset_id != "" do
    if String.starts_with?(asset_id, ["http://", "https://"]) do
      upload!(lecture, path)
    else
      {asset_id, lecture.duration_seconds || 60}
    end
  end

  def ensure_uploaded!(%Lecture{} = lecture, path), do: upload!(lecture, path)

  defp upload!(lecture, path) do
    IO.puts("Uploading seed video #{lecture.position}/5 to Cloudflare Stream…")
    %{id: uid, url: upload_url} = create_upload!(lecture)
    video = File.read!(path)

    case Req.post(upload_url,
           form_multipart: [
             file: {video, filename: Path.basename(path), content_type: "video/mp4"}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        wait_until_ready!(uid, 1)

      {:ok, %{status: status, body: body}} ->
        raise "Cloudflare upload failed (#{status}): #{inspect(body)}"

      {:error, reason} ->
        raise "Cloudflare upload failed: #{inspect(reason)}"
    end
  end

  defp create_upload!(lecture) do
    case Cloudflare.create_upload(lecture, []) do
      {:ok, upload} ->
        upload

      {:error, {:cloudflare, status, body}} ->
        raise "Cloudflare rejected the direct-upload request (HTTP #{status}): #{inspect(body)}"

      {:error, reason} ->
        raise "Could not create a Cloudflare direct upload: #{inspect(reason)}"
    end
  end

  defp wait_until_ready!(uid, attempt) when attempt <= @max_poll_attempts do
    case Cloudflare.upload_status(uid) do
      {:ok, {:ready, ^uid, duration}} ->
        {uid, duration}

      {:ok, status} when status in [:waiting, :processing] ->
        Process.sleep(@poll_interval_ms)
        wait_until_ready!(uid, attempt + 1)

      {:error, reason} ->
        raise "Cloudflare could not process seed video #{uid}: #{inspect(reason)}"
    end
  end

  defp wait_until_ready!(uid, _attempt) do
    raise "Timed out waiting for Cloudflare to process seed video #{uid}"
  end
end

admin_attrs = %{
  name: "Wasomi Admin",
  email: "admin@example.com",
  phone: "254700000001",
  password: "123456"
}

student_attrs = %{
  name: "One Student",
  email: "student@example.com",
  phone: "254700000002",
  password: "123456"
}

seed_video_path = Wasomi.Seeds.CloudflareVideo.build_one_minute_video!()

course_attrs = %{
  slug: "the-human-stack",
  title: "The Human Stack by Alvas",
  description:
    "Turn complex technical thinking into clear messages, persuasive presentations, and productive workplace conversations.",
  thumbnail_key: "/images/human-stack-course.svg",
  price_minor: 1_500_000,
  currency: "KES",
  status: :published,
  position: 1
}

certificate_attrs = %{
  certificate_enabled: true,
  certificate_issuer_name: "Wasomi Academy",
  certificate_signatory_name: "Alvas Mwangi",
  certificate_signatory_title: "Lead Instructor"
}

# {module title, module description, [{lecture title, lecture summary}]}
modules = [
  {"Communication as a Technical Superpower",
   "Build clear, intentional communication skills across five concise lessons.",
   [
     {"Why the human stack matters", "How communication compounds the value of technical work."},
     {"Diagnosing communication breakdowns", "Spot where a message loses its audience."},
     {"Reading the room", "Understand what an audience knows and cares about."},
     {"The one-sentence message", "Compress a complex update into one decisive sentence."},
     {"Turning clarity into action", "Give an audience a clear decision or next step."}
   ]}
]

# Open-ended questions (Catalog.LectureQuestion) — the free-text prompts the
# learner answers under the player, scored by the AI grader in production.
lecture_questions = [
  {"In your own words, what problem does this lesson solve for a technical team?",
   "It closes the gap between doing good technical work and having that work understood, trusted, and acted on by other people."},
  {"Describe a time a technically correct message still failed to land. What was missing?",
   "Usually the audience's context or the decision they needed to make — the message was accurate but not aimed at anyone in particular."}
]

# Multiple-choice questions reused for the lecture quiz, the module quiz, and
# the study-hub practice set — three different surfaces, same shape of data.
# {prompt, [{label, correct?}], explanation}
multiple_choice = [
  {"What is the clearest sign that a technical message has failed?",
   [
     {"The audience cannot say what to do next", true},
     {"The slides were not branded", false},
     {"The talk ran under time", false},
     {"Nobody asked a question", false}
   ], "A message succeeds when the audience leaves knowing the decision or action it implies."},
  {"Before writing an update, what should you decide first?",
   [
     {"The outcome you want from the reader", true},
     {"The font and colour scheme", false},
     {"How many charts to include", false},
     {"Which tool to draft it in", false}
   ], "Every other choice — length, detail, format — follows from the outcome you're after."},
  {"An analogy is most useful when it:",
   [
     {"Maps the unfamiliar onto something the audience already knows", true},
     {"Shows how much you know about the topic", false},
     {"Replaces the need for any evidence", false},
     {"Makes the explanation longer", false}
   ], "Analogy borrows existing understanding; it doesn't replace evidence."}
]

flashcards = [
  {"The human stack", "The communication skills that make technical work legible and trusted."},
  {"One-sentence message", "The single sentence an audience should repeat after you finish."},
  {"Audience-first framing",
   "Start from the decision the audience must make, not from your work."},
  {"Signal vs detail", "Detail supports a claim; it never substitutes for making one."}
]

transcript_text = """
Welcome to the human stack. Most technical people are trained to make things
correct, and almost never trained to make them land. Those are two different
skills, and the second one is what this course is about.

Start with the outcome. Before you open a document or a deck, decide what you
want the audience to understand, decide, or do. Everything else — how long you
speak, how much detail you include, which chart you show — falls out of that
one choice.

Then read the room. The same result, presented to an engineer, a manager, and
a customer, needs three different framings. Not three different truths, three
different entry points into the same truth.

Finally, compress. If you cannot state your message in one sentence, the
audience will not be able to repeat it. And a message nobody can repeat is a
message that stops with you.
"""

# Small upsert helper: every entity here is keyed so re-running the seeds
# updates in place rather than duplicating or crashing on a unique index.
upsert = fn changeset ->
  if changeset.data.id, do: Repo.update!(changeset), else: Repo.insert!(changeset)
end

Repo.transaction(
  fn ->
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    admin =
      case Repo.get_by(User, email: admin_attrs.email) do
        nil ->
          {:ok, admin} = Accounts.register_user(admin_attrs)

          admin
          |> User.role_changeset(%{role: :admin})
          |> Changeset.put_change(:phone, admin_attrs.phone)
          |> Changeset.put_change(:confirmed_at, now)
          |> Repo.update!()

        admin ->
          admin
          |> User.password_changeset(%{password: admin_attrs.password})
          |> Changeset.put_change(:name, admin_attrs.name)
          |> Changeset.put_change(:phone, admin_attrs.phone)
          |> Changeset.put_change(:role, :admin)
          |> Changeset.put_change(:confirmed_at, admin.confirmed_at || now)
          |> Repo.update!()
      end

    student =
      case Repo.get_by(User, email: student_attrs.email) do
        nil ->
          {:ok, student} = Accounts.register_user(student_attrs)

          student
          |> User.role_changeset(%{role: :learner})
          |> Changeset.put_change(:phone, student_attrs.phone)
          |> Changeset.put_change(:confirmed_at, now)
          |> Repo.update!()

        student ->
          student
          |> User.password_changeset(%{password: student_attrs.password})
          |> Changeset.put_change(:name, student_attrs.name)
          |> Changeset.put_change(:phone, student_attrs.phone)
          |> Changeset.put_change(:role, :learner)
          |> Changeset.put_change(:confirmed_at, student.confirmed_at || now)
          |> Repo.update!()
      end

    course =
      case Repo.get_by(Course, slug: course_attrs.slug) do
        nil -> %Course{}
        existing -> existing
      end
      |> Course.changeset(course_attrs)
      |> upsert.()
      |> Course.certificate_changeset(certificate_attrs)
      |> Repo.update!()

    # Keep this seed course deterministic when upgrading from an older seed
    # shape that had multiple modules.
    Repo.delete_all(from(m in CourseModule, where: m.course_id == ^course.id and m.position > 1))

    modules
    |> Enum.with_index(1)
    |> Enum.each(fn {{module_title, module_description, lectures}, module_position} ->
      course_module =
        case Repo.get_by(CourseModule, course_id: course.id, position: module_position) do
          nil -> %CourseModule{}
          existing -> existing
        end
        |> CourseModule.changeset(%{
          course_id: course.id,
          title: module_title,
          description: module_description,
          position: module_position
        })
        |> upsert.()

      Repo.delete_all(
        from(l in Lecture, where: l.module_id == ^course_module.id and l.position > 5)
      )

      # Module-level quiz, published so the course itself is publishable and
      # the study hub's timed-quiz mode has questions to serve.
      quiz =
        case Repo.get_by(Quiz, module_id: course_module.id) do
          nil -> %Quiz{}
          existing -> existing
        end
        |> Quiz.changeset(%{
          module_id: course_module.id,
          title: "#{module_title} check",
          description: "Confirm the key ideas from this module.",
          passing_score_percent: 70,
          active: true,
          published_at: now
        })
        |> upsert.()

      multiple_choice
      |> Enum.with_index(1)
      |> Enum.each(fn {{prompt, options, explanation}, position} ->
        case Repo.get_by(Question, quiz_id: quiz.id, position: position) do
          nil -> %Question{}
          existing -> Repo.preload(existing, :question_options)
        end
        |> Question.changeset(%{
          quiz_id: quiz.id,
          prompt: prompt,
          explanation: explanation,
          status: :published,
          position: position,
          question_options:
            Enum.with_index(options, 1)
            |> Enum.map(fn {{label, correct}, option_position} ->
              %{label: label, correct: correct, position: option_position}
            end)
        })
        |> upsert.()
      end)

      Enum.with_index(lectures, 1)
      |> Enum.each(fn {{lecture_title, lecture_description}, lecture_position} ->
        lecture =
          case Repo.get_by(Lecture, module_id: course_module.id, position: lecture_position) do
            nil -> %Lecture{}
            existing -> existing
          end
          |> Lecture.changeset(%{
            module_id: course_module.id,
            title: lecture_title,
            description: lecture_description,
            position: lecture_position
          })
          |> upsert.()

        {video_asset_id, duration_seconds} =
          Wasomi.Seeds.CloudflareVideo.ensure_uploaded!(lecture, seed_video_path)

        lecture =
          lecture
          |> Lecture.changeset(%{
            video_provider: :cloudflare,
            video_asset_id: video_asset_id,
            duration_seconds: duration_seconds
          })
          |> Repo.update!()

        # Transcript — the source every AI generator reads from, pre-seeded as
        # `:ready` so admin generation screens have something to work with.
        case Repo.get_by(LectureTranscript, lecture_id: lecture.id) do
          nil -> %LectureTranscript{}
          existing -> existing
        end
        |> LectureTranscript.changeset(%{
          lecture_id: lecture.id,
          status: :ready,
          text: transcript_text
        })
        |> upsert.()

        lecture_questions
        |> Enum.with_index(1)
        |> Enum.each(fn {{question, answer}, position} ->
          case Repo.get_by(LectureQuestion, lecture_id: lecture.id, position: position) do
            nil -> %LectureQuestion{}
            existing -> existing
          end
          |> LectureQuestion.changeset(%{
            lecture_id: lecture.id,
            question: question,
            answer: answer,
            position: position
          })
          |> upsert.()
        end)

        # Lecture quiz with published questions — this is what gates the next
        # lecture (see `Wasomi.Learning.lecture_unlocked?/3`).
        lecture_quiz =
          case Repo.get_by(LectureQuiz, lecture_id: lecture.id) do
            nil -> %LectureQuiz{}
            existing -> existing
          end
          |> LectureQuiz.changeset(%{
            lecture_id: lecture.id,
            title: "#{lecture_title} check",
            passing_score_percent: 70,
            active: true,
            published_at: now
          })
          |> upsert.()

        multiple_choice
        |> Enum.take(2)
        |> Enum.with_index(1)
        |> Enum.each(fn {{prompt, options, _explanation}, position} ->
          case Repo.get_by(LectureQuizQuestion,
                 lecture_quiz_id: lecture_quiz.id,
                 position: position
               ) do
            nil -> %LectureQuizQuestion{}
            existing -> Repo.preload(existing, :question_options)
          end
          |> LectureQuizQuestion.changeset(%{
            lecture_quiz_id: lecture_quiz.id,
            prompt: prompt,
            status: :published,
            position: position,
            question_options:
              Enum.with_index(options, 1)
              |> Enum.map(fn {{label, correct}, option_position} ->
                %{label: label, correct: correct, position: option_position}
              end)
          })
          |> upsert.()
        end)

        # Study-hub artefacts, lecture-scoped.
        flashcard_set =
          case Repo.get_by(FlashcardSet, lecture_id: lecture.id) do
            nil -> %FlashcardSet{}
            existing -> existing
          end
          |> FlashcardSet.changeset(%{
            lecture_id: lecture.id,
            status: :ready,
            cards_generated_count: length(flashcards),
            generated_at: now
          })
          |> upsert.()

        flashcards
        |> Enum.with_index(1)
        |> Enum.each(fn {{front, back}, position} ->
          case Repo.get_by(Flashcard, flashcard_set_id: flashcard_set.id, position: position) do
            nil -> %Flashcard{}
            existing -> existing
          end
          |> Flashcard.changeset(%{
            flashcard_set_id: flashcard_set.id,
            front: front,
            back: back,
            position: position
          })
          |> upsert.()
        end)

        practice_set =
          case Repo.get_by(PracticeSet, lecture_id: lecture.id) do
            nil -> %PracticeSet{}
            existing -> existing
          end
          |> PracticeSet.changeset(%{
            lecture_id: lecture.id,
            status: :ready,
            questions_generated_count: length(multiple_choice),
            generated_at: now
          })
          |> upsert.()

        multiple_choice
        |> Enum.with_index(1)
        |> Enum.each(fn {{prompt, options, explanation}, position} ->
          case Repo.get_by(PracticeSetQuestion,
                 practice_set_id: practice_set.id,
                 position: position
               ) do
            nil -> %PracticeSetQuestion{}
            existing -> Repo.preload(existing, :practice_set_question_options)
          end
          |> PracticeSetQuestion.changeset(%{
            practice_set_id: practice_set.id,
            prompt: prompt,
            explanation: explanation,
            position: position,
            practice_set_question_options:
              Enum.with_index(options, 1)
              |> Enum.map(fn {{label, correct}, option_position} ->
                %{label: label, correct: correct, position: option_position}
              end)
          })
          |> upsert.()
        end)
      end)
    end)

    # The learner: an active, paid enrollment so the course opens straight into
    # the player rather than the checkout page.
    paid_at = DateTime.add(now, -30, :day)

    enrollment =
      case Repo.get_by(Enrollment, user_id: student.id, course_id: course.id) do
        nil -> %Enrollment{}
        existing -> existing
      end
      |> Enrollment.changeset(%{
        user_id: student.id,
        course_id: course.id,
        status: :active,
        enrolled_at: paid_at,
        activated_at: paid_at
      })
      |> upsert.()

    provider_reference = "KBI-SEED-PAID-STUDENT-#{String.upcase(course.slug)}"

    payment =
      case Repo.get_by(Payment, provider_reference: provider_reference) do
        nil -> %Payment{}
        existing -> existing
      end
      |> Payment.changeset(%{
        user_id: student.id,
        course_id: course.id,
        enrollment_id: enrollment.id,
        provider: :paystack,
        provider_reference: provider_reference,
        amount_minor: course.price_minor,
        currency: course.currency,
        status: :successful,
        paid_at: paid_at,
        raw_payload: %{
          "seeded" => true,
          "status" => "success",
          "reference" => provider_reference
        }
      })
      |> upsert.()

    Repo.update_all(from(p in Payment, where: p.id == ^payment.id), set: [inserted_at: paid_at])

    admin
  end,
  timeout: :infinity
)

File.rm(seed_video_path)

IO.puts("Seeded admin:   #{admin_attrs.email} / #{admin_attrs.password}")
IO.puts("Seeded learner: #{student_attrs.email} / #{student_attrs.password}")

IO.puts(
  "Seeded 1 published course (#{course_attrs.slug}) with 5 one-minute Cloudflare Stream videos, " <>
    "captions requested, transcripts, lecture quizzes, and a final module quiz."
)
