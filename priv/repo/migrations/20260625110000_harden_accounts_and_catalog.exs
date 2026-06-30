defmodule Wasomi.Repo.Migrations.HardenAccountsAndCatalog do
  use Ecto.Migration

  def change do
    create constraint(:users, :users_phone_must_be_normalized, check: "phone ~ '^2547[0-9]{8}$'")

    create constraint(:users, :users_role_must_be_valid, check: "role IN ('learner', 'admin')")

    alter table(:courses) do
      modify :slug, :string, null: false
      modify :title, :string, null: false
      modify :subtitle, :string, null: false
      modify :description, :text, null: false
      modify :thumbnail_key, :string, null: false
      modify :price_minor, :integer, null: false
      modify :currency, :string, null: false, default: "KES"
      modify :status, :string, null: false, default: "draft"
      modify :position, :integer, null: false, default: 1
    end

    create constraint(:courses, :courses_price_must_be_non_negative, check: "price_minor >= 0")

    create constraint(:courses, :courses_position_must_be_positive, check: "position > 0")

    create constraint(:courses, :courses_status_must_be_valid,
             check: "status IN ('draft', 'published')"
           )

    alter table(:modules) do
      modify :title, :string, null: false
      modify :description, :text, null: false
      modify :position, :integer, null: false

      modify :course_id, references(:courses, on_delete: :delete_all),
        null: false,
        from: references(:courses, on_delete: :nothing)
    end

    create constraint(:modules, :modules_position_must_be_positive, check: "position > 0")

    alter table(:lectures) do
      modify :title, :string, null: false
      modify :description, :text, null: false
      modify :video_provider, :string, null: false
      modify :video_asset_id, :string, null: false
      modify :duration_seconds, :integer, null: false
      modify :position, :integer, null: false

      modify :module_id, references(:modules, on_delete: :delete_all),
        null: false,
        from: references(:modules, on_delete: :nothing)
    end

    create constraint(:lectures, :lectures_duration_must_be_positive,
             check: "duration_seconds > 0"
           )

    create constraint(:lectures, :lectures_position_must_be_positive, check: "position > 0")

    create constraint(:lectures, :lectures_video_provider_must_be_valid,
             check: "video_provider IN ('mux', 'cloudflare', 'bunny')"
           )
  end
end
