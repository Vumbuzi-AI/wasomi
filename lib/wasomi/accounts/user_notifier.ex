defmodule Wasomi.Accounts.UserNotifier do
  import Swoosh.Email

  alias Wasomi.Emails.Template
  alias Wasomi.Mailer

  # Delivers the email using the application mailer, rendering both the HTML
  # and text bodies from the same branded template so they can't drift apart.
  defp deliver(recipient, subject, assigns) do
    email =
      new()
      |> to(recipient)
      |> from({"Wasomi", "contact@example.com"})
      |> subject(subject)
      |> html_body(Template.render(assigns))
      |> text_body(Template.render_text(assigns))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    name = recipient_name(user)

    deliver(user.email, "Confirmation instructions", %{
      title: "Welcome to Wasomi! Let's confirm your email",
      intro: "Hi #{name},",
      body: [
        "You're one step away from activating your account and starting your learning journey.",
        "Click the button below, then confirm on the page that opens. We'll sign you in automatically and take you to your learner dashboard."
      ],
      cta: %{label: "Confirm account", url: url}
    })
  end

  @doc """
  Emails a one-time magic login link. `url` carries the raw login token.
  """
  def deliver_magic_link(user, url) do
    deliver(user.email, "Your Wasomi login link", %{
      title: "Log in to Wasomi",
      intro: "Hi #{recipient_name(user)},",
      body: [
        "Use the button below to log in. The link works once and expires in 15 minutes.",
        "If you didn't ask to log in, you can safely ignore this email."
      ],
      cta: %{label: "Log in to Wasomi", url: url}
    })
  end

  @doc """
  Welcomes a user after their account is confirmed.
  """
  def deliver_welcome(user) do
    name = recipient_name(user)

    deliver(user.email, "Welcome to Wasomi", %{
      title: "Welcome aboard, #{name}!",
      intro: "Hi #{name},",
      body: [
        "Your account is confirmed and ready to go!",
        "Get ready to start learning and level up your skills with practical, high-impact courses."
      ],
      cta: %{label: "Explore courses", url: "#{WasomiWeb.Endpoint.url()}/courses"}
    })
  end

  @doc """
  Tells a learner an admin has granted them access to a course.
  """
  def deliver_course_access_granted(user, course) do
    name = recipient_name(user)
    url = "#{WasomiWeb.Endpoint.url()}/learn/courses/#{course.slug}"

    deliver(user.email, "You now have access to #{course.title}", %{
      title: "You're in! Access granted to #{course.title}",
      intro: Template.rich(["Hi ", {:bold, name}, ","]),
      body: [
        Template.rich([
          "Great news — you've officially been granted full access to \"",
          {:bold, course.title},
          "\" on Wasomi!"
        ]),
        "Get learning and stay ahead! Your course materials are unlocked and ready. Jump in now to master real-world skills at your own pace."
      ],
      cta: %{label: "Start learning now", url: url}
    })
  end

  @doc """
  Tells a learner that a generated certificate is ready to download.
  """
  def deliver_certificate_issued(certificate) do
    title = certificate.course.title
    name = recipient_name(certificate.user)
    url = "#{WasomiWeb.Endpoint.url()}/certificates/#{certificate.id}/download"

    deliver(certificate.user.email, "Your Wasomi certificate is ready", %{
      title: "You earned it!",
      intro: "Hi #{name},",
      body: [
        "Huge congratulations on completing \"#{title}\"! Your hard work paid off, and your official certificate is ready to download.",
        "Sign in to your Wasomi account to claim your certificate and celebrate your achievement."
      ],
      cta: %{label: "Download certificate", url: url}
    })
  end

  @doc """
  Nudges a learner who enrolled but never started a lecture — touch `touch`
  (1, 2, or 3) of the sequence, each with its own subject/tone.
  """
  def deliver_reengagement_never_started(user, course, touch \\ 1)
      when touch in [1, 2, 3] do
    url = "#{WasomiWeb.Endpoint.url()}/learn/courses/#{course.slug}"
    {subject, title, body} = never_started_copy(touch, course)

    deliver(user.email, subject, %{
      title: title,
      intro: Template.rich(["Hi ", {:bold, recipient_name(user)}, ","]),
      body: body,
      cta: %{label: "Start learning now", url: url}
    })
  end

  defp never_started_copy(1, course) do
    {
      "Your seat in \"#{course.title}\" is ready when you are",
      "Haven't started yet? Let's fix that.",
      [
        Template.rich([
          "You enrolled in \"",
          {:bold, course.title},
          "\" and your course materials have been waiting for you."
        ]),
        "It only takes a few minutes to get through your first lecture — jump in today and start building momentum."
      ]
    }
  end

  defp never_started_copy(2, course) do
    {
      "Still thinking about \"#{course.title}\"?",
      "No pressure — your seat is still here.",
      [
        Template.rich([
          "Just checking in — your spot in \"",
          {:bold, course.title},
          "\" hasn't gone anywhere."
        ]),
        "Whenever you're ready, your first lecture is one click away."
      ]
    }
  end

  defp never_started_copy(3, course) do
    {
      "Last call: your seat in \"#{course.title}\"",
      "One last reminder, then we'll leave you be.",
      [
        Template.rich([
          "This is the last nudge you'll get about \"",
          {:bold, course.title},
          "\" — after this we'll stop reminding you."
        ]),
        "Your access isn't going anywhere, so there's genuinely no rush. We just didn't want you to miss it."
      ]
    }
  end

  @doc """
  Nudges a learner who made progress in a course, then went quiet — touch
  `touch` (1, 2, or 3) of the sequence, each with its own subject/tone.
  """
  def deliver_reengagement_gone_quiet(user, course, touch \\ 1)
      when touch in [1, 2, 3] do
    url = "#{WasomiWeb.Endpoint.url()}/learn/courses/#{course.slug}"
    {subject, title, body} = gone_quiet_copy(touch, course)

    deliver(user.email, subject, %{
      title: title,
      intro: Template.rich(["Hi ", {:bold, recipient_name(user)}, ","]),
      body: body,
      cta: %{label: "Resume learning", url: url}
    })
  end

  defp gone_quiet_copy(1, course) do
    {
      "Pick up right where you left off in \"#{course.title}\"",
      "We miss you in \"#{course.title}\"!",
      [
        Template.rich([
          "You made great progress in \"",
          {:bold, course.title},
          "\", then things went quiet. Life happens!"
        ]),
        "Your progress is saved, so you can jump back in exactly where you left off whenever you're ready."
      ]
    }
  end

  defp gone_quiet_copy(2, course) do
    {
      "Your progress in \"#{course.title}\" is still saved",
      "Still thinking about finishing up?",
      [
        Template.rich([
          "Everything you completed in \"",
          {:bold, course.title},
          "\" is exactly where you left it — nothing to redo."
        ]),
        "Even a few minutes picks up where you stopped."
      ]
    }
  end

  defp gone_quiet_copy(3, course) do
    {
      "One last nudge for \"#{course.title}\"",
      "Last check-in — then we'll stop reminding you.",
      [
        Template.rich([
          "This is the last nudge you'll get about \"",
          {:bold, course.title},
          "\"."
        ]),
        "Your progress stays saved either way, so there's no rush — we just didn't want you to lose track of it."
      ]
    }
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    name = recipient_name(user)

    deliver(user.email, "Reset password instructions", %{
      title: "Need to reset your password?",
      intro: "Hi #{name},",
      body: [
        "No worries! Click the link below to securely reset your password and get back to learning.",
        "If you didn't request a password reset, you can safely ignore this email."
      ],
      cta: %{label: "Reset password", url: url}
    })
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    name = recipient_name(user)

    deliver(user.email, "Update email instructions", %{
      title: "Confirm your new email address",
      intro: "Hi #{name},",
      body: [
        "You requested an update to your email address.",
        "Click the button below to verify your new email address and complete the change."
      ],
      cta: %{label: "Update email", url: url}
    })
  end

  @doc """
  Confirms a completed course payment to the learner, ecommerce-receipt
  style — a one-line order summary plus a pointer to the downloadable PDF
  receipt. Expects `payment` with `:user` and `:course` preloaded.
  """
  def deliver_payment_receipt(payment) do
    name = recipient_name(payment.user)
    base = WasomiWeb.Endpoint.url()

    deliver(payment.user.email, "Your Wasomi receipt for #{payment.course.title}", %{
      title: "Payment confirmed — you're enrolled",
      intro: Template.rich(["Hi ", {:bold, name}, ","]),
      body: [
        Template.rich([
          "Thanks for your payment. You now have full access to \"",
          {:bold, payment.course.title},
          "\"."
        ]),
        Template.rich([
          {:bold, payment.course.title},
          " — ",
          {:bold, Wasomi.Payments.format_amount(payment)},
          ", paid via ",
          provider_name(payment.provider),
          on_date(payment.paid_at),
          "."
        ]),
        "A full PDF receipt is available any time from your Receipts page."
      ],
      cta: %{label: "Start learning now", url: "#{base}/learn/courses/#{payment.course.slug}"}
    })
  end

  defp provider_name(:paystack), do: "Paystack"
  defp provider_name(:mpesa), do: "M-Pesa"
  defp provider_name(other), do: other |> to_string() |> String.capitalize()

  defp on_date(%DateTime{} = at), do: " on " <> Calendar.strftime(at, "%B %-d, %Y")
  defp on_date(_), do: ""

  @doc """
  Tells an active member about a new course-channel announcement.
  """
  def deliver_channel_announcement(user, course, excerpt) do
    name = recipient_name(user)
    url = "#{WasomiWeb.Endpoint.url()}/learn/courses/#{course.slug}?tab=discussion"

    deliver(user.email, "New announcement in #{course.title}", %{
      title: "New announcement in #{course.title}",
      intro: Template.rich(["Hi ", {:bold, name}, ","]),
      body: [
        Template.rich([
          "There's a new announcement in the \"",
          {:bold, course.title},
          "\" channel:"
        ]),
        "“#{excerpt}”"
      ],
      cta: %{label: "Open the channel", url: url}
    })
  end

  defp recipient_name(%{first_name: first}) when is_binary(first) and byte_size(first) > 0,
    do: first

  defp recipient_name(%{name: name}) when is_binary(name) and byte_size(name) > 0,
    do: name |> String.split() |> List.first()

  defp recipient_name(%{email: email}) when is_binary(email), do: email
  defp recipient_name(_), do: "there"
end
