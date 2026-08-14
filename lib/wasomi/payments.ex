defmodule Wasomi.Payments do
  @moduledoc """
  Payment lifecycle and verified enrollment activation.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Wasomi.Accounts.User
  alias Wasomi.Catalog.Course
  alias Wasomi.Enrollments
  alias Wasomi.Paginate
  alias Wasomi.Payments.Payment
  alias Wasomi.Repo

  @paystack_verify_fields ~w(id reference status amount currency paid_at channel gateway_response)
  @paystack_initialize_fields ~w(authorization_url access_code reference)

  def list_payments, do: Repo.all(Payment)

  @doc """
  Lists successful payments that can be presented to a learner as receipts.

  Failed and pending attempts are deliberately omitted.
  """
  def list_receipts_for_user(%User{id: user_id}) do
    Payment
    |> where([payment], payment.user_id == ^user_id and payment.status == :successful)
    |> order_by([payment], desc: payment.paid_at, desc: payment.id)
    |> preload(:course)
    |> Repo.all()
  end

  def format_amount(%Payment{amount_minor: amount, currency: currency}) do
    format_minor(amount, currency)
  end

  @doc """
  Formats a raw minor-unit amount (e.g. a summed revenue figure) for display,
  matching the convention used for individual payment receipts.
  """
  def format_minor(amount, currency \\ "KES") do
    (amount || 0)
    |> Money.new(currency)
    |> Money.to_string(symbol: false, code: true)
  end

  @doc """
  Total revenue, in minor units, across all successful payments.
  """
  def total_revenue_minor do
    Payment
    |> where([p], p.status == :successful)
    |> Repo.aggregate(:sum, :amount_minor) || 0
  end

  @doc """
  Successful revenue, in minor units, keyed by `course_id`.
  """
  def revenue_minor_by_course do
    Payment
    |> where([p], p.status == :successful)
    |> group_by([p], p.course_id)
    |> select([p], {p.course_id, sum(p.amount_minor)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Successful revenue, in minor units, for a single course.
  """
  def revenue_minor_for_course(course_id) do
    Payment
    |> where([p], p.status == :successful and p.course_id == ^course_id)
    |> Repo.aggregate(:sum, :amount_minor) || 0
  end

  @doc """
  Counts successful payments keyed by `course_id` — the "Paid" side of the
  admin revenue report's "Enrolled" vs "Paid" columns (see
  `Enrollments.count_by_course/0` for the "Enrolled" side).
  """
  def count_successful_by_course do
    Payment
    |> where([p], p.status == :successful)
    |> group_by([p], p.course_id)
    |> select([p], {p.course_id, count(p.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The most recent successful payment's `paid_at`, keyed by `course_id`.
  """
  def last_paid_at_by_course do
    Payment
    |> where([p], p.status == :successful)
    |> group_by([p], p.course_id)
    |> select([p], {p.course_id, max(p.paid_at)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Successful revenue, in minor units, keyed by `user_id`.
  """
  def revenue_minor_by_user do
    Payment
    |> where([p], p.status == :successful)
    |> group_by([p], p.user_id)
    |> select([p], {p.user_id, sum(p.amount_minor)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Counts payments, optionally scoped to a status.
  """
  def count_payments, do: Repo.aggregate(Payment, :count)

  def count_payments(status) do
    Payment
    |> where([p], p.status == ^status)
    |> Repo.aggregate(:count)
  end

  @doc """
  Lists the most recent payments with the learner and course preloaded.
  """
  def list_recent_payments(limit \\ 25) do
    Payment
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(^limit)
    |> preload([:user, :course])
    |> Repo.all()
  end

  @sortable_payment_fields ~w(date reference learner course amount status)a

  @doc """
  Returns a `Wasomi.Paginate.Page` of payments, with the learner and
  course preloaded.

  ## Options

    * `:status` - only payments in this status (`:pending`, `:successful`, `:failed`).
    * `:search` - case-insensitive match against learner name/email, course
      title, or provider reference.
    * `:sort_by` - one of #{inspect(@sortable_payment_fields)} (default `:date`,
      which sorts by `inserted_at` — the same field the "Date" column
      displays, not `paid_at`, which is `nil` for pending/failed payments
      and would misorder most of the table).
    * `:sort_dir` - `:asc` or `:desc` (default `:desc`).
    * `:page` / `:page_size`

  """
  def list_payments_page(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    sort_by = Keyword.get(opts, :sort_by, :date)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)

    page_result =
      Payment
      |> join(:left, [p], u in assoc(p, :user))
      |> join(:left, [p, u], c in assoc(p, :course))
      |> filter_payment_status(Keyword.get(opts, :status))
      |> filter_payment_search(Keyword.get(opts, :search))
      |> sort_payments(sort_by, sort_dir)
      |> Paginate.paginate(page, page_size)

    %{page_result | entries: Repo.preload(page_result.entries, [:user, :course])}
  end

  defp filter_payment_status(query, nil), do: query
  defp filter_payment_status(query, status), do: where(query, [p], p.status == ^status)

  defp filter_payment_search(query, search) when search in [nil, ""], do: query

  defp filter_payment_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [p, u, c],
      ilike(u.name, ^pattern) or ilike(u.email, ^pattern) or ilike(c.title, ^pattern) or
        ilike(p.provider_reference, ^pattern)
    )
  end

  # `p.id` is the tiebreaker for every column, in the *same* direction as
  # the primary sort — not always ascending. Same-second inserts otherwise
  # tie on `inserted_at`, and an always-ascending tiebreak would silently
  # put the newest of those ties last when sorting "newest first" (desc).
  defp sort_payments(query, :reference, dir),
    do: order_by(query, [p], [{^dir, p.provider_reference}, {^dir, p.id}])

  defp sort_payments(query, :learner, dir),
    do: order_by(query, [p, u], [{^dir, u.name}, {^dir, p.id}])

  defp sort_payments(query, :course, dir),
    do: order_by(query, [p, u, c], [{^dir, c.title}, {^dir, p.id}])

  defp sort_payments(query, :amount, dir),
    do: order_by(query, [p], [{^dir, p.amount_minor}, {^dir, p.id}])

  defp sort_payments(query, :status, dir),
    do: order_by(query, [p], [{^dir, p.status}, {^dir, p.id}])

  defp sort_payments(query, _date_or_unknown, dir),
    do: order_by(query, [p], [{^dir, p.inserted_at}, {^dir, p.id}])

  @doc """
  Lists every payment made against a course, learner preloaded, newest first.
  """
  def list_payments_for_course(course_id) do
    Payment
    |> where([p], p.course_id == ^course_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc """
  Lists every payment a user has made (any status), course preloaded, newest
  first. Intended for the admin student detail page.
  """
  def list_payments_for_user(user_id) do
    Payment
    |> where([p], p.user_id == ^user_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> preload(:course)
    |> Repo.all()
  end

  def get_payment!(id), do: Repo.get!(Payment, id)
  def get_payment_by_reference(reference), do: Repo.get_by(Payment, provider_reference: reference)

  def create_payment(attrs \\ %{}) do
    %Payment{}
    |> Payment.changeset(attrs)
    |> Repo.insert()
  end

  def update_payment(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(attrs)
    |> Repo.update()
  end

  def delete_payment(%Payment{} = payment), do: Repo.delete(payment)
  def change_payment(%Payment{} = payment, attrs \\ %{}), do: Payment.changeset(payment, attrs)

  def initialize_checkout(
        %User{} = user,
        %Course{} = course,
        phone \\ nil,
        provider \\ provider()
      ) do
    if course.is_free do
      case Enrollments.enroll_free_course(user, course) do
        {:ok, enrollment} ->
          {:ok, %{enrollment: enrollment, payment: nil, authorization_url: nil}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      with {:ok, %{enrollment: enrollment, payment: payment}} <-
             create_pending_checkout(user, course, phone),
           {:ok, response} <- provider.initiate(Repo.preload(payment, :user)),
           {:ok, authorization_url} <- Map.fetch(response, "authorization_url"),
           {:ok, payment} <- store_initialization(payment, response) do
        {:ok,
         %{
           enrollment: enrollment,
           payment: payment,
           authorization_url: authorization_url
         }}
      else
        :error -> {:error, :missing_authorization_url}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def create_pending_checkout(%User{} = user, %Course{} = course, phone \\ nil) do
    Repo.transaction(fn ->
      with {:ok, enrollment} <- Enrollments.create_pending_enrollment(user, course),
           {:ok, payment} <-
             create_payment(%{
               user_id: user.id,
               course_id: course.id,
               enrollment_id: enrollment.id,
               provider: :paystack,
               provider_reference: payment_reference(),
               amount_minor: course.price_minor,
               currency: course.currency,
               phone: phone,
               status: :pending,
               raw_payload: %{}
             }) do
        %{enrollment: enrollment, payment: payment}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def process_paystack_reference(reference, provider \\ provider()) when is_binary(reference) do
    case get_payment_by_reference(reference) do
      nil ->
        {:error, :payment_not_found}

      %Payment{status: :successful} = payment ->
        {:ok,
         %{
           payment: payment,
           enrollment: Repo.get!(Wasomi.Enrollments.Enrollment, payment.enrollment_id)
         }}

      %Payment{status: :failed} ->
        {:error, :payment_failed}

      %Payment{} = payment ->
        with {:ok, verification} <- provider.verify(reference),
             :ok <- validate_verification(payment, verification) do
          complete_verified_payment(payment, verification)
        else
          {:error, {:payment_failed, verification}} -> mark_failed(reference, verification)
          {:error, _reason} = error -> error
        end
    end
  end

  @doc """
  Admin-triggered live re-verification of a single pending payment against the
  configured provider (Paystack, including its M-Pesa mobile-money channel).

  Requires the acting user to be an admin, mirroring the defense-in-depth
  check `Enrollments.grant_access/3` already performs rather than relying
  solely on the caller's route-level guard.

  Reuses the same validation and completion path as the webhook flow, so a
  provider "success" atomically marks the payment successful and activates
  the enrollment, broadcasting `{:payment_confirmed, enrollment}` to the
  learner. Returns the raw provider verification payload alongside the
  result so the caller can surface the provider's own status/reason.
  """
  def verify_transaction(payment_id, %User{role: :admin}) do
    case Repo.get(Payment, payment_id) do
      nil -> {:error, :payment_not_found}
      payment -> do_verify_transaction(payment)
    end
  end

  def verify_transaction(_payment_id, %User{}), do: {:error, :forbidden}
  def verify_transaction(_payment_id, _caller), do: {:error, :forbidden}

  defp do_verify_transaction(%Payment{status: :successful} = payment) do
    {:ok,
     %{
       payment: payment,
       enrollment: Repo.get!(Wasomi.Enrollments.Enrollment, payment.enrollment_id),
       verification: nil
     }}
  end

  defp do_verify_transaction(%Payment{status: :failed} = payment) do
    {:error, {:already_failed, payment}}
  end

  defp do_verify_transaction(%Payment{} = payment) do
    with {:ok, verification} <- provider().verify(payment.provider_reference),
         :ok <- validate_verification(payment, verification) do
      case complete_verified_payment(payment, verification) do
        {:ok, result} -> {:ok, Map.put(result, :verification, verification)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:payment_failed, verification}} ->
        case mark_failed(payment.provider_reference, verification) do
          {:ok, %{payment: confirmed_payment} = result} ->
            confirmed_verification = confirmed_payment.raw_payload["verification"] || verification
            {:ok, Map.put(result, :verification, confirmed_verification)}

          {:error, {:payment_failed, _payment}} ->
            {:error, {:provider_declined, verification}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def record_webhook_event(reference, event) do
    case get_payment_by_reference(reference) do
      nil ->
        {:error, :payment_not_found}

      payment ->
        update_payment(payment, %{
          raw_payload: Map.put(payment.raw_payload || %{}, "webhook", sanitize_webhook(event))
        })
    end
  end

  def list_stale_pending_payments(cutoff \\ DateTime.add(DateTime.utc_now(), -120, :second)) do
    Payment
    |> where([p], p.provider == :paystack and p.status == :pending)
    |> where([p], p.inserted_at <= ^DateTime.truncate(cutoff, :second))
    |> order_by([p], asc: p.inserted_at)
    |> Repo.all()
  end

  def subscribe(%User{id: id}), do: Phoenix.PubSub.subscribe(Wasomi.PubSub, "user:#{id}")

  defp complete_verified_payment(payment, verification) do
    result =
      Multi.new()
      |> Multi.run(:payment, fn repo, _changes ->
        locked =
          Payment
          |> where([p], p.id == ^payment.id)
          |> lock("FOR UPDATE")
          |> repo.one!()

        if locked.status == :successful do
          {:ok, locked}
        else
          locked
          |> Payment.changeset(%{
            status: :successful,
            paid_at: paid_at(verification),
            raw_payload:
              Map.put(
                locked.raw_payload || %{},
                "verification",
                sanitize(verification, @paystack_verify_fields)
              )
          })
          |> repo.update()
        end
      end)
      |> Multi.run(:enrollment, fn _repo, %{payment: completed_payment} ->
        enrollment = Repo.get!(Wasomi.Enrollments.Enrollment, completed_payment.enrollment_id)
        Enrollments.activate_enrollment(enrollment)
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{payment: payment, enrollment: enrollment}} ->
        Phoenix.PubSub.broadcast(
          Wasomi.PubSub,
          "user:#{payment.user_id}",
          {:payment_confirmed, enrollment}
        )

        {:ok, %{payment: payment, enrollment: enrollment}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp mark_failed(reference, verification) do
    payment = get_payment_by_reference(reference)

    if payment.status == :successful do
      {:ok,
       %{
         payment: payment,
         enrollment: Repo.get!(Wasomi.Enrollments.Enrollment, payment.enrollment_id)
       }}
    else
      update_payment(payment, %{
        status: :failed,
        paid_at: nil,
        raw_payload:
          Map.put(
            payment.raw_payload || %{},
            "verification",
            sanitize(verification, @paystack_verify_fields)
          )
      })
      |> case do
        {:ok, payment} -> {:error, {:payment_failed, payment}}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp store_initialization(payment, response) do
    update_payment(payment, %{
      raw_payload:
        Map.put(
          payment.raw_payload || %{},
          "initialization",
          sanitize(response, @paystack_initialize_fields)
        )
    })
  end

  defp validate_verification(payment, verification) do
    cond do
      to_string(verification["reference"]) != payment.provider_reference ->
        {:error, :reference_mismatch}

      verification["status"] != "success" ->
        {:error, {:payment_failed, verification}}

      verification["amount"] != payment.amount_minor ->
        {:error, :amount_mismatch}

      String.upcase(to_string(verification["currency"])) != payment.currency ->
        {:error, :currency_mismatch}

      true ->
        :ok
    end
  end

  defp sanitize(map, fields) when is_map(map), do: Map.take(map, fields)
  defp sanitize(_value, _fields), do: %{}

  defp sanitize_webhook(event) do
    %{
      "event" => event["event"],
      "data" => sanitize(event["data"] || %{}, @paystack_verify_fields)
    }
  end

  defp paid_at(%{"paid_at" => paid_at}) when is_binary(paid_at) do
    case DateTime.from_iso8601(paid_at) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> now()
    end
  end

  defp paid_at(_verification), do: now()
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp payment_reference,
    do: "KBI-" <> (Ecto.UUID.generate() |> String.replace("-", "") |> String.upcase())

  defp provider, do: Application.fetch_env!(:wasomi, :payment_provider)
end
