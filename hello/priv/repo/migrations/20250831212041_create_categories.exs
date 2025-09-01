defmodule Hello.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:title])
  end
end
