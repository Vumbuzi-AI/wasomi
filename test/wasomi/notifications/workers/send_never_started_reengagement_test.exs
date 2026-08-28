defmodule Wasomi.Notifications.Workers.SendNeverStartedReengagementTest do
  use Wasomi.DataCase
  use Oban.Testing, repo: Wasomi.Repo

  import ExUnit.CaptureLog
  import Swoosh.TestAssertions
  import Wasomi.AccountsFixtures
  import Wasomi.CatalogFixtures
  import Wasomi.EnrollmentsFixtures

  alias Wasomi.Notifications.Notification
  alias Wasomi.Notifications.Workers.SendNeverStartedReengagement

  test "emails every active enrollment past the threshold with zero progress" do
    %{user: user, course: course} = enrolled_days_ago(10)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])

    assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")

    assert Repo.get_by(Notification,
             user_id: user.id,
             course_id: course.id,
             kind: :reengagement_never_started
           )
  end

  test "does not email an enrollment younger than the threshold" do
    enrolled_days_ago(3)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])

    assert_no_email_sent()
  end

  test "running twice does not send a second email for the same enrollment" do
    enrolled_days_ago(10)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])
    assert_email_sent()

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])
    assert_no_email_sent()

    assert Repo.aggregate(Notification, :count) == 1
  end

  test "returns an error for Oban retry when email delivery fails" do
    previous_mailer_config = Application.get_env(:wasomi, Wasomi.Mailer)
    on_exit(fn -> Application.put_env(:wasomi, Wasomi.Mailer, previous_mailer_config) end)
    Application.put_env(:wasomi, Wasomi.Mailer, adapter: __MODULE__.FailingMailerAdapter)

    enrolled_days_ago(10)

    capture_log(fn ->
      assert {:error, [{:error, :provider_down}]} =
               Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])
    end)

    assert_no_email_sent()
    assert Repo.aggregate(Notification, :count) == 0
  end

  test "one enrollment's delivery failure doesn't block the nudge for the rest of the batch" do
    previous_mailer_config = Application.get_env(:wasomi, Wasomi.Mailer)
    on_exit(fn -> Application.put_env(:wasomi, Wasomi.Mailer, previous_mailer_config) end)

    %{user: failing_user, course: failing_course} = enrolled_days_ago(10)
    %{user: ok_user, course: ok_course} = enrolled_days_ago(10)

    Application.put_env(:wasomi, Wasomi.Mailer,
      adapter: __MODULE__.FailsForOneRecipientMailerAdapter,
      fail_for: failing_user.email
    )

    capture_log(fn ->
      assert {:error, [{:error, :provider_down}]} =
               Oban.Testing.perform_job(SendNeverStartedReengagement, %{}, [])
    end)

    assert_email_sent(subject: "Your seat in \"#{ok_course.title}\" is ready when you are")

    assert Repo.get_by(Notification,
             user_id: ok_user.id,
             course_id: ok_course.id,
             kind: :reengagement_never_started
           )

    refute Repo.get_by(Notification,
             user_id: failing_user.id,
             course_id: failing_course.id,
             kind: :reengagement_never_started
           )
  end

  test "a touch: 2 job sends the touch 2 email to an enrollment whose touch 1 is old enough" do
    %{user: user, course: course} = enrolled_days_ago(20)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{"touch" => 1}, [])
    assert_email_sent(subject: "Your seat in \"#{course.title}\" is ready when you are")

    touch1 =
      Repo.get_by!(Notification,
        user_id: user.id,
        course_id: course.id,
        kind: :reengagement_never_started
      )

    backdate_notification!(touch1, 8)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{"touch" => 2}, [])
    assert_email_sent(subject: "Still thinking about \"#{course.title}\"?")

    assert Repo.get_by(Notification,
             user_id: user.id,
             course_id: course.id,
             kind: :reengagement_never_started_2
           )
  end

  test "a touch: 2 job does not fire for an enrollment whose touch 1 was sent too recently" do
    enrolled_days_ago(20)

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{"touch" => 1}, [])
    assert_email_sent()

    assert :ok = Oban.Testing.perform_job(SendNeverStartedReengagement, %{"touch" => 2}, [])
    assert_no_email_sent()
  end

  defp backdate_notification!(%Notification{id: id}, days) do
    sent_at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    Notification
    |> Ecto.Query.where([n], n.id == ^id)
    |> Repo.update_all(set: [inserted_at: sent_at])
  end

  defp enrolled_days_ago(days) do
    user = user_fixture()
    course = course_fixture(status: :published)

    enrolled_at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    enrollment_fixture(
      user_id: user.id,
      course_id: course.id,
      status: :active,
      enrolled_at: enrolled_at
    )

    %{user: user, course: course}
  end

  defmodule FailingMailerAdapter do
    use Swoosh.Adapter

    def deliver(_email, _config), do: {:error, :provider_down}
  end

  # Fails only for the configured `fail_for` recipient, delegating every
  # other delivery to the real `Test` adapter — needed so `assert_email_sent`
  # can still see the ones that were supposed to succeed.
  defmodule FailsForOneRecipientMailerAdapter do
    use Swoosh.Adapter

    alias Swoosh.Adapters.Test, as: TestAdapter

    def deliver(%Swoosh.Email{to: [{_name, address} | _]} = email, config) do
      if address == config[:fail_for] do
        {:error, :provider_down}
      else
        TestAdapter.deliver(email, config)
      end
    end
  end
end
