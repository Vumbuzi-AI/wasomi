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
    deliver(user.email, "Confirmation instructions", %{
      title: "Welcome to Wasomi! Let's confirm your email",
      intro: "Hi #{user.email},",
      body: [
        "You're one step away from unlocking practical business and technology masterclasses.",
        "Click the button below to verify your email address and jump right into learning."
      ],
      cta: %{label: "Confirm account", url: url}
    })
  end

  @doc """
  Welcomes a user after their account is confirmed.
  """
  def deliver_welcome(user) do
    deliver(user.email, "Welcome to Wasomi Business Institute", %{
      title: "Welcome aboard, #{user.name}!",
      intro: "Hi #{user.name},",
      body: [
        "Your account is confirmed and ready to go!",
        "Get ready to level up your career with practical, high-impact masterclasses built for technology and business professionals."
      ],
      cta: %{label: "Explore courses", url: "#{WasomiWeb.Endpoint.url()}/courses"}
    })
  end

  @doc """
  Tells a learner an admin has granted them access to a course.
  """
  def deliver_course_access_granted(user, course) do
    url = "#{WasomiWeb.Endpoint.url()}/learn/courses/#{course.slug}"

    deliver(user.email, "You now have access to #{course.title}", %{
      title: "You're in! Access granted to #{course.title}",
      intro: "Hi #{user.name},",
      body: [
        "Great news — you've officially been granted full access to \"#{course.title}\" on Wasomi Business Institute!",
        "Get learning and stay ahead! Your course materials are unlocked and ready. Jump in now to master real-world skills at your own pace."
      ],
      cta: %{label: "Start learning now", url: url}
    })
  end

  @doc """
  Tells a learner that a generated certificate is ready to download.
  """
  def deliver_certificate_issued(certificate) do
    url = "#{WasomiWeb.Endpoint.url()}/certificates/#{certificate.id}/download"

    deliver(certificate.user.email, "Your Wasomi certificate is ready", %{
      title: "You earned it!",
      intro: "Hi #{certificate.user.name},",
      body: [
        "Huge congratulations on completing \"#{certificate.course.title}\"! Your hard work paid off, and your official certificate is ready to download.",
        "Sign in to your Wasomi account to claim your certificate and celebrate your achievement."
      ],
      cta: %{label: "Download certificate", url: url}
    })
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", %{
      title: "Need to reset your password?",
      intro: "Hi #{user.email},",
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
    deliver(user.email, "Update email instructions", %{
      title: "Confirm your new email address",
      intro: "Hi #{user.email},",
      body: [
        "You requested an update to your email address.",
        "Click the button below to verify your new email address and complete the change."
      ],
      cta: %{label: "Update email", url: url}
    })
  end
end
