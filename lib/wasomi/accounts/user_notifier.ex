defmodule Wasomi.Accounts.UserNotifier do
  import Swoosh.Email

  alias Wasomi.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Wasomi", "contact@example.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Welcomes a user after their account is confirmed.
  """
  def deliver_welcome(user) do
    deliver(user.email, "Welcome to Wasomi Business Institute", """

    Hi #{user.name},

    Welcome to Wasomi Business Institute. Your account is confirmed and you
    can now explore our practical courses for technology professionals.

    Start learning: #{WasomiWeb.Endpoint.url()}/courses

    — The Wasomi team
    """)
  end

  @doc """
  Tells a learner that a generated certificate is ready to download.
  """
  def deliver_certificate_issued(certificate) do
    title =
      case certificate.type do
        :module -> certificate.module.title
        :course -> certificate.course.title
      end

    url = "#{WasomiWeb.Endpoint.url()}/certificates/#{certificate.id}/download"

    deliver(certificate.user.email, "Your Wasomi certificate is ready", """

    Hi #{certificate.user.name},

    Your certificate for "#{title}" is ready.

    Download it securely: #{url}

    This link requires you to sign in to your Wasomi account.

    — The Wasomi team
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
