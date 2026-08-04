defmodule Rumbl.Repo.Migrations.CreateAnnotations do
  use Ecto.Migration

  def change do
    create table(:annotations) do
      add :body, :text
      add :at, :integer
      add :user_id, references(:users, on_delete: :nothing)
      add :video_id, references(:videos, on_delete: :nothing)

      timestamps()
    end
    create index(:annotations, [:user_id])
    create index(:annotations, [:video_id])

  end
end
