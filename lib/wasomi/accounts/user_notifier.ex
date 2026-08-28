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
      intro: "Hi #{name},",
      body: [
        "Great news — you've officially been granted full access to \"#{course.title}\" on Wasomi!",
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

  defp recipient_name(%{name: name}) when is_binary(name) and byte_size(name) > 0, do: name
  defp recipient_name(%{email: email}) when is_binary(email), do: email
  defp recipient_name(_), do: "there"
end
