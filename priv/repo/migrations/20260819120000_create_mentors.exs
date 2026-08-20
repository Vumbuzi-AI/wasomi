defmodule Wasomi.Repo.Migrations.CreateMentors do
  use Ecto.Migration

  def change do
    create table(:mentors) do
      add :name, :string
      add :role, :string
      add :photo_key, :string
      add :twitter_url, :string
      add :facebook_url, :string
      add :linkedin_url, :string
      add :position, :integer
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end
  end
end
