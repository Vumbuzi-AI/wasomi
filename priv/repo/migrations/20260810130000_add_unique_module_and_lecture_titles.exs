defmodule Wasomi.Repo.Migrations.AddUniqueModuleAndLectureTitles do
  use Ecto.Migration

  def change do
    create unique_index(:modules, ["course_id", "lower(title)"],
             name: :modules_course_id_title_index
           )

    create unique_index(:lectures, ["module_id", "lower(title)"],
             name: :lectures_module_id_title_index
           )
  end
end
