defmodule Rumbl.Repo.Migrations.CreateCategory do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :name, :string, null: false

      timestamps() # function call parenthesis not in book!
    end

    create unique_index(:categories, [:name])
  end
end
