defmodule Wasomi.Repo.Migrations.AddQuizPublishingFields do
  use Ecto.Migration

  def change do
    alter table(:quizzes) do
      add :active, :boolean, null: false, default: false
      add :published_at, :utc_datetime
    end

    alter table(:questions) do
      add :explanation, :text
    end

    create index(:quizzes, [:active])
  end
end
