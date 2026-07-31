defmodule Wasomi.Repo.Migrations.CreateQuizGenerations do
  use Ecto.Migration

  def change do
    create table(:quiz_generations) do
      add :quiz_id, references(:quizzes, on_delete: :delete_all), null: false
      add :requested_by_id, references(:users, on_delete: :delete_all), null: false
      add :source_filename, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :questions_generated_count, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:quiz_generations, [:quiz_id])

    create constraint(:quiz_generations, :quiz_generations_status_must_be_valid,
             check: "status IN ('pending', 'processing', 'ready', 'failed')"
           )

    alter table(:questions) do
      add :quiz_generation_id, references(:quiz_generations, on_delete: :nilify_all)
    end

    create index(:questions, [:quiz_generation_id])
  end
end
