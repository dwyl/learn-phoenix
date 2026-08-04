defmodule Ecto.Integration.Migration do
  use Ecto.Migration

  def change do
    # IO.puts "TESTING MIGRATION LOCK"
    # Process.sleep(10000)

    create table(:users, comment: "users table") do
      add :name, :string, comment: "name column"
      add :custom_id, :uuid
      timestamps()
    end

    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer
      add :blob, :binary
      add :bid, :binary_id
      add :uuid, :uuid
      add :meta, :map
      add :links, {:map, :string}
      add :intensities, {:map, :float}
      add :public, :boolean
      add :cost, :decimal, precision: 2, scale: 1
      add :visits, :integer
      add :wrapped_visits, :integer
      add :intensity, :float
      add :author_id, :integer
      add :posted, :date
      add :read_only, :string
      timestamps(null: true)
    end

    create table(:posts_users, primary_key: false) do
      add :post_id, references(:posts)
      add :user_id, references(:users)
    end

    create table(:posts_users_pk) do
      add :post_id, references(:posts)
      add :user_id, references(:users)
      timestamps()
    end

    # Add a unique index on uuid. We use this
    # to verify the behaviour that the index
    # only matters if the UUID column is not NULL.
    create unique_index(:posts, [:uuid], comment: "posts index")

    create table(:permalinks) do
      add :uniform_resource_locator, :string
      add :title, :string
      add :post_id, references(:posts)
      add :user_id, references(:users)
    end

    create unique_index(:permalinks, [:post_id])
    create unique_index(:permalinks, [:uniform_resource_locator])

    create table(:comments) do
      add :text, :string, size: 100
      add :lock_version, :integer, default: 1
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end

    create table(:customs, primary_key: false) do
      add :bid, :binary_id, primary_key: true
      add :uuid, :uuid
    end

    create unique_index(:customs, [:uuid])

    create table(:customs_customs, primary_key: false) do
      add :custom_id1, references(:customs, column: :bid, type: :binary_id)
      add :custom_id2, references(:customs, column: :bid, type: :binary_id)
    end

    create table(:barebones) do
      add :num, :integer
    end

    create table(:transactions) do
      add :num, :integer
    end

    create table(:lock_counters) do
      add :count, :integer
    end

    create table(:orders) do
      add :label, :string
      add :item, :map
      add :items, :map
      add :meta, :map
      add :permalink_id, references(:permalinks)
    end

    unless :array_type in ExUnit.configuration()[:exclude] do
      create table(:tags) do
        add :ints,  {:array, :integer}
        add :uuids, {:array, :uuid}, default: []
        add :items, {:array, :map}
      end

      create table(:array_loggings) do
        add :uuids, {:array, :uuid}, default: []
        timestamps()
      end
    end

    unless :bitstring_type in ExUnit.configuration()[:exclude] do
      create table(:bitstrings) do
        add :bs,  :bitstring
        add :bs_with_default, :bitstring, default: <<42::6>>
        add :bs_with_size, :bitstring, size: 10
      end
    end

    if Code.ensure_loaded?(Duration) do
      unless :duration_type in ExUnit.configuration()[:exclude] do
        create table(:durations) do
          add :dur, :duration
          add :dur_with_fields, :duration, fields: "MONTH"
          add :dur_with_precision, :duration, precision: 4
          add :dur_with_fields_and_precision, :duration, fields: "HOUR TO SECOND", precision: 1
          add :dur_with_default, :duration, default: "10 MONTH"
        end
      end
    end

    create table(:composite_pk, primary_key: false) do
      add :a, :integer, primary_key: true
      add :b, :integer, primary_key: true
      add :name, :string
    end

    create table(:corrupted_pk, primary_key: false) do
      add :a, :string
    end

    create table(:posts_users_composite_pk) do
      add :post_id, references(:posts), primary_key: true
      add :user_id, references(:users), primary_key: true
      timestamps()
    end

    create unique_index(:posts_users_composite_pk, [:post_id, :user_id])

    create table(:usecs) do
      add :naive_datetime_usec, :naive_datetime_usec
      add :utc_datetime_usec, :utc_datetime_usec
    end

    create table(:bits) do
      add :bit, :bit
    end

    create table(:loggings, primary_key: false) do
      add :bid, :binary_id, primary_key: true
      add :int, :integer
      add :uuid, :uuid
      timestamps()
    end
  end
end
