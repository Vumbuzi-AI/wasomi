defmodule Wasomi.Reviews.CourseReview do
  use Ecto.Schema
  import Ecto.Changeset

  schema "course_reviews" do
    field :rating, :integer
    field :body, :string
    belongs_to :user, Wasomi.Accounts.User
    belongs_to :course, Wasomi.Catalog.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(review, attrs) do
    review
    |> cast(attrs, [:rating, :body, :user_id, :course_id])
    |> update_change(:body, &normalize_body/1)
    |> validate_required([:rating, :user_id, :course_id])
    |> validate_inclusion(:rating, 1..5, message: "must be between 1 and 5 stars")
    |> validate_length(:body, max: 2000)
    |> unique_constraint([:user_id, :course_id])
    |> check_constraint(:rating, name: :course_reviews_rating_between_1_and_5)
    |> assoc_constraint(:user)
    |> assoc_constraint(:course)
  end

  defp normalize_body(nil), do: nil

  defp normalize_body(body) when is_binary(body) do
    case String.trim(body) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
