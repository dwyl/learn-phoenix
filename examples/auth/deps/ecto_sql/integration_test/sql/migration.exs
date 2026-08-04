defmodule Ecto.Integration.MigrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Integration.{TestRepo, PoolRepo}

  defmodule CreateMigration do
    use Ecto.Migration

    @table table(:create_table_migration)
    @index index(:create_table_migration, [:value], unique: true)

    def up do
      create @table do
        add :value, :integer
      end
      create @index
    end

    def down do
      drop @index
      drop @table
    end
  end

  defmodule AddColumnMigration do
    use Ecto.Migration

    def up do
      create table(:add_col_migration) do
        add :value, :integer
      end

      alter table(:add_col_migration) do
        add :to_be_added, :integer
      end

      execute "INSERT INTO add_col_migration (value, to_be_added) VALUES (1, 2)"
    end

    def down do
      drop table(:add_col_migration)
    end
  end

  defmodule AlterColumnMigration do
    use Ecto.Migration

    def up do
      create table(:alter_col_migration) do
        add :from_null_to_not_null, :integer
        add :from_not_null_to_null, :integer, null: false

        add :from_default_to_no_default, :integer, default: 0
        add :from_no_default_to_default, :integer
      end

      alter table(:alter_col_migration) do
        modify :from_null_to_not_null, :string, null: false
        modify :from_not_null_to_null, :string, null: true

        modify :from_default_to_no_default, :integer, default: nil
        modify :from_no_default_to_default, :integer, default: 0
      end

      execute "INSERT INTO alter_col_migration (from_null_to_not_null) VALUES ('foo')"
    end

    def down do
      drop table(:alter_col_migration)
    end
  end

  defmodule AlterColumnFromMigration do
    use Ecto.Migration

    def change do
      create table(:modify_from_products) do
        add :value, :integer
        add :nullable, :integer, null: false
      end

      if direction() == :up do
        flush()
        PoolRepo.insert_all "modify_from_products", [[value: 1, nullable: 1]]
      end

      alter table(:modify_from_products) do
        modify :value, :bigint, from: :integer
        modify :nullable, :bigint, null: true, from: {:integer, null: false}
      end
    end
  end

  defmodule AlterColumnFromPkeyMigration do
    use Ecto.Migration

    def change do
      create table(:modify_from_authors, primary_key: false) do
        add :id, :integer, primary_key: true
      end
      create table(:modify_from_posts) do
        add :author_id, references(:modify_from_authors, type: :integer)
      end

      if direction() == :up do
        flush()
        PoolRepo.insert_all "modify_from_authors", [[id: 1]]
        PoolRepo.insert_all "modify_from_posts", [[author_id: 1]]
      end

      alter table(:modify_from_posts) do
        # remove the constraints modify_from_posts_author_id_fkey
        modify :author_id, :integer, from: references(:modify_from_authors, type: :integer)
      end
      alter table(:modify_from_authors) do
        modify :id, :bigint, from: :integer
      end
      alter table(:modify_from_posts) do
        # add the constraints modify_from_posts_author_id_fkey
        modify :author_id, references(:modify_from_authors, type: :bigint), from: :integer
      end
    end
  end

  defmodule AlterForeignKeyOnDeleteMigration do
    use Ecto.Migration

    def up do
      create table(:alter_fk_users)

      create table(:alter_fk_posts) do
        add :alter_fk_user_id, :id
      end

      alter table(:alter_fk_posts) do
        modify :alter_fk_user_id, references(:alter_fk_users, on_delete: :nilify_all)
      end
    end

    def down do
      drop table(:alter_fk_posts)
      drop table(:alter_fk_users)
    end
  end

  defmodule AlterForeignKeyOnUpdateMigration do
    use Ecto.Migration

    def up do
      create table(:alter_fk_users)

      create table(:alter_fk_posts) do
        add :alter_fk_user_id, :id
      end

      alter table(:alter_fk_posts) do
        modify :alter_fk_user_id, references(:alter_fk_users, on_update: :update_all)
      end
    end

    def down do
      drop table(:alter_fk_posts)
      drop table(:alter_fk_users)
    end
  end

  defmodule DropColumnMigration do
    use Ecto.Migration

    def up do
      create table(:drop_col_migration) do
        add :value, :integer
        add :to_be_removed, :integer
      end

      execute "INSERT INTO drop_col_migration (value, to_be_removed) VALUES (1, 2)"

      alter table(:drop_col_migration) do
        remove :to_be_removed
      end
    end

    def down do
      drop table(:drop_col_migration)
    end
  end

  defmodule RenameColumnMigration do
    use Ecto.Migration

    def up do
      create table(:rename_col_migration) do
        add :to_be_renamed, :integer
      end

      rename table(:rename_col_migration), :to_be_renamed, to: :was_renamed

      execute "INSERT INTO rename_col_migration (was_renamed) VALUES (1)"
    end

    def down do
      drop table(:rename_col_migration)
    end
  end

  defmodule OnDeleteMigration do
    use Ecto.Migration

    def up do
      create table(:parent1)
      create table(:parent2)

      create table(:ref_migration) do
        add :parent1, references(:parent1, on_delete: :nilify_all)
      end

      alter table(:ref_migration) do
        add :parent2, references(:parent2, on_delete: :delete_all)
      end
    end

    def down do
      drop table(:ref_migration)
      drop table(:parent1)
      drop table(:parent2)
    end
  end

  defmodule OnDeleteNilifyColumnsMigration do
    use Ecto.Migration

    def up do
      create table(:parent) do
        add :col1, :integer
        add :col2, :integer
      end

      create unique_index(:parent, [:id, :col1, :col2])

      create table(:ref) do
        add :col1, :integer
        add :col2, :integer
        add :parent_id,
            references(:parent,
              with: [col1: :col1, col2: :col2],
              on_delete: {:nilify, [:parent_id, :col2]}
            )
      end
    end

    def down do
      drop table(:ref)
      drop table(:parent)
    end
  end

  defmodule OnDeleteDefaultAllMigration do
    use Ecto.Migration

    def up do
      create table(:parent, primary_key: [type: :bigint]) do
        add :col1, :integer
        add :col2, :integer
      end

      create unique_index(:parent, [:id, :col1, :col2])

      create table(:ref) do
        add :col1, :integer, default: 2
        add :col2, :integer, default: 3

        add :parent_id,
            references(:parent,
              with: [col1: :col1, col2: :col2],
              on_delete: :default_all
            ), default: 1
      end
    end

    def down do
      drop table(:ref)
      drop table(:parent)
    end
  end

  defmodule OnDeleteDefaultColumnsMigration do
    use Ecto.Migration

    def up do
      create table(:parent, primary_key: [type: :bigint]) do
        add :col1, :integer
        add :col2, :integer
      end

      create unique_index(:parent, [:id, :col1, :col2])

      create table(:ref) do
        add :col1, :integer, default: 2
        add :col2, :integer, default: 3

        add :parent_id,
            references(:parent,
              with: [col1: :col1, col2: :col2],
              on_delete: {:default, [:parent_id, :col2]}
            ), default: 1
      end
    end

    def down do
      drop table(:ref)
      drop table(:parent)
    end
  end

  defmodule CompositeForeignKeyMigration do
    use Ecto.Migration

    def change do
      create table(:composite_parent) do
        add :key_id, :integer
      end

      create unique_index(:composite_parent, [:id, :key_id])

      create table(:composite_child) do
        add :parent_key_id, :integer
        add :parent_id, references(:composite_parent, with: [parent_key_id: :key_id])
      end
    end
  end

  defmodule RenameIndexMigration do
    use Ecto.Migration

    def change do
      create table(:composite_parent) do
        add :key_id, :integer
      end

      create unique_index(:composite_parent, [:id, :key_id], name: "old_index_name")

      rename index(:composite_parent, [:id, :key_id], name: "old_index_name"), to: "new_index_name"
    end
  end

  defmodule ReferencesRollbackMigration do
    use Ecto.Migration

    def change do
      create table(:parent) do
        add :name, :string
      end

      create table(:child) do
        add :parent_id, references(:parent)
      end
    end
  end

  defmodule RenameMigration do
    use Ecto.Migration

    @table_current table(:posts_migration)
    @table_new table(:new_posts_migration)

    def up do
      create @table_current
      rename @table_current, to: @table_new
    end

    def down do
      drop @table_new
    end
  end

  defmodule PrefixMigration do
    use Ecto.Migration

    @prefix "ecto_prefix_test"

    def up do
      execute TestRepo.create_prefix(@prefix)
      create table(:first, prefix: @prefix)
      create table(:second, prefix: @prefix) do
        add :first_id, references(:first)
      end
    end

    def down do
      drop table(:second, prefix: @prefix)
      drop table(:first, prefix: @prefix)
      execute TestRepo.drop_prefix(@prefix)
    end
  end

  defmodule NoSQLMigration do
    use Ecto.Migration

    def up do
      create table(:collection, options: [capped: true])
      execute create: "collection"
    end
  end

  defmodule Parent do
    use Ecto.Schema

    schema "parent" do
    end
  end

  defmodule NoErrorTableMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:existing) do
        add :name, :string
      end

      create_if_not_exists table(:existing) do
        add :name, :string
      end

      create_if_not_exists table(:existing)

      drop_if_exists table(:existing)
      drop_if_exists table(:existing)
    end
  end

  defmodule NoErrorIndexMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists index(:posts, [:title])
      create_if_not_exists index(:posts, [:title])
      drop_if_exists index(:posts, [:title])
      drop_if_exists index(:posts, [:title])
    end
  end

  defmodule InferredDropIndexMigration do
    use Ecto.Migration

    def change do
      create index(:posts, [:title])
    end
  end

  defmodule AlterPrimaryKeyMigration do
    use Ecto.Migration

    def change do
      create table(:no_pk, primary_key: false) do
        add :dummy, :string
      end
      alter table(:no_pk) do
        add :id, :serial, primary_key: true
      end
    end
  end


  defmodule AddColumnIfNotExistsMigration do
    use Ecto.Migration

    def up do
      create table(:add_col_if_not_exists_migration)

      alter table(:add_col_if_not_exists_migration) do
        add_if_not_exists :value, :integer
        add_if_not_exists :to_be_added, :integer
      end

      execute "INSERT INTO add_col_if_not_exists_migration (value, to_be_added) VALUES (1, 2)"
    end

    def down do
      drop table(:add_col_if_not_exists_migration)
    end
  end

  defmodule DropColumnIfExistsMigration do
    use Ecto.Migration

    def up do
      create table(:drop_col_if_exists_migration) do
        add :value, :integer
        add :to_be_removed, :integer
      end

      execute "INSERT INTO drop_col_if_exists_migration (value, to_be_removed) VALUES (1, 2)"

      alter table(:drop_col_if_exists_migration) do
        remove_if_exists :to_be_removed, :integer
      end
    end

    def down do
      drop table(:drop_col_if_exists_migration)
    end
  end

  defmodule NoErrorOnConditionalColumnMigration do
    use Ecto.Migration

    def up do
      create table(:no_error_on_conditional_column_migration)

      alter table(:no_error_on_conditional_column_migration) do
        add_if_not_exists  :value, :integer
        add_if_not_exists  :value, :integer

        remove_if_exists :value, :integer
        remove_if_exists :value, :integer
      end
    end

    def down do
      drop table(:no_error_on_conditional_column_migration)
    end
  end

  import Ecto.Query, only: [from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]

  # Avoid migration out of order warnings
  @moduletag :capture_log
  @base_migration 1_000_000

  setup do
    {:ok, migration_number: System.unique_integer([:positive]) + @base_migration}
  end

  test "create and drop table and indexes", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, CreateMigration, log: false)
    assert :ok == down(PoolRepo, num, CreateMigration, log: false)
  end

  test "correctly infers how to drop index", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, InferredDropIndexMigration, log: false)
    assert :ok == down(PoolRepo, num, InferredDropIndexMigration, log: false)
  end

  test "supports on delete", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, OnDeleteMigration, log: false)

    parent1 = PoolRepo.insert! Ecto.put_meta(%Parent{}, source: "parent1")
    parent2 = PoolRepo.insert! Ecto.put_meta(%Parent{}, source: "parent2")

    writer = "INSERT INTO ref_migration (parent1, parent2) VALUES (#{parent1.id}, #{parent2.id})"
    PoolRepo.query!(writer)

    reader = from r in "ref_migration", select: {r.parent1, r.parent2}
    assert PoolRepo.all(reader) == [{parent1.id, parent2.id}]

    PoolRepo.delete!(parent1)
    assert PoolRepo.all(reader) == [{nil, parent2.id}]

    PoolRepo.delete!(parent2)
    assert PoolRepo.all(reader) == []

    assert :ok == down(PoolRepo, num, OnDeleteMigration, log: false)
  end

  test "composite foreign keys", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, CompositeForeignKeyMigration, log: false)

    PoolRepo.insert_all("composite_parent", [[key_id: 2]])
    assert [id] = PoolRepo.all(from p in "composite_parent", select: p.id)

    catch_error(PoolRepo.insert_all("composite_child", [[parent_id: id, parent_key_id: 1]]))
    assert {1, nil} = PoolRepo.insert_all("composite_child", [[parent_id: id, parent_key_id: 2]])

    assert :ok == down(PoolRepo, num, CompositeForeignKeyMigration, log: false)
  end

  test "rename index", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, RenameIndexMigration, log: false)
    assert :ok == down(PoolRepo, num, RenameIndexMigration, log: false)
  end

  test "rolls back references in change/1", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, ReferencesRollbackMigration, log: false)
    assert :ok == down(PoolRepo, num, ReferencesRollbackMigration, log: false)
  end

  test "create table if not exists and drop table if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorTableMigration, log: false)
  end

  @tag :create_index_if_not_exists
  test "create index if not exists and drop index if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorIndexMigration, log: false)
  end

  test "raises on NoSQL migrations", %{migration_number: num} do
    assert_raise ArgumentError, ~r"does not support keyword lists in :options", fn ->
      up(PoolRepo, num, NoSQLMigration, log: false)
    end
  end

  @tag :add_column
  test "add column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AddColumnMigration, log: false)
    assert [2] == PoolRepo.all from p in "add_col_migration", select: p.to_be_added
    :ok = down(PoolRepo, num, AddColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterColumnMigration, log: false)

    assert ["foo"] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_null_to_not_null
    assert [nil] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_not_null_to_null
    assert [nil] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_default_to_no_default
    assert [0] ==
           PoolRepo.all from p in "alter_col_migration", select: p.from_no_default_to_default

    query = "INSERT INTO `alter_col_migration` (\"from_not_null_to_null\") VALUES ('foo')"
    assert catch_error(PoolRepo.query!(query))

    :ok = down(PoolRepo, num, AlterColumnMigration, log: false)
  end

  @tag :modify_column
  test "modify column with from", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterColumnFromMigration, log: false)

    assert [1] ==
           PoolRepo.all from p in "modify_from_products", select: p.value

    :ok = down(PoolRepo, num, AlterColumnFromMigration, log: false)
  end

  @tag :alter_primary_key
  test "modify column with from and pkey", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterColumnFromPkeyMigration, log: false)

    assert [1] ==
           PoolRepo.all from p in "modify_from_posts", select: p.author_id

    :ok = down(PoolRepo, num, AlterColumnFromPkeyMigration, log: false)
  end

  @tag :alter_foreign_key
  test "modify foreign key's on_delete constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterForeignKeyOnDeleteMigration, log: false)

    PoolRepo.insert_all("alter_fk_users", [[]])
    assert [id] = PoolRepo.all from p in "alter_fk_users", select: p.id

    PoolRepo.insert_all("alter_fk_posts", [[alter_fk_user_id: id]])
    PoolRepo.delete_all("alter_fk_users")
    assert [nil] == PoolRepo.all from p in "alter_fk_posts", select: p.alter_fk_user_id

    :ok = down(PoolRepo, num, AlterForeignKeyOnDeleteMigration, log: false)
  end

  @tag :assigns_id_type
  test "modify foreign key's on_update constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterForeignKeyOnUpdateMigration, log: false)

    PoolRepo.insert_all("alter_fk_users", [[]])
    assert [id] = PoolRepo.all from p in "alter_fk_users", select: p.id

    PoolRepo.insert_all("alter_fk_posts", [[alter_fk_user_id: id]])
    PoolRepo.update_all("alter_fk_users", set: [id: 12345])
    assert [12345] == PoolRepo.all from p in "alter_fk_posts", select: p.alter_fk_user_id

    PoolRepo.delete_all("alter_fk_posts")
    :ok = down(PoolRepo, num, AlterForeignKeyOnUpdateMigration, log: false)
  end

  @tag :remove_column
  test "remove column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, DropColumnMigration, log: false)
    assert catch_error(PoolRepo.all from p in "drop_col_migration", select: p.to_be_removed)
    :ok = down(PoolRepo, num, DropColumnMigration, log: false)
  end

  @tag :rename_column
  test "rename column", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, RenameColumnMigration, log: false)
    assert [1] == PoolRepo.all from p in "rename_col_migration", select: p.was_renamed
    :ok = down(PoolRepo, num, RenameColumnMigration, log: false)
  end

  @tag :rename_table
  test "rename table", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, RenameMigration, log: false)
    assert :ok == down(PoolRepo, num, RenameMigration, log: false)
  end

  @tag :prefix
  test "prefix", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, PrefixMigration, log: false)
    assert :ok == down(PoolRepo, num, PrefixMigration, log: false)
  end

  @tag :alter_primary_key
  test "alter primary key", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AlterPrimaryKeyMigration, log: false)
    assert :ok == down(PoolRepo, num, AlterPrimaryKeyMigration, log: false)
  end

  @tag :add_column_if_not_exists
  @tag :remove_column_if_exists
  test "add if not exists and remove if exists does not raise on failure", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, NoErrorOnConditionalColumnMigration, log: false)
    assert :ok == down(PoolRepo, num, NoErrorOnConditionalColumnMigration, log: false)
  end

  @tag :add_column_if_not_exists
  test "add column if not exists", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, AddColumnIfNotExistsMigration, log: false)
    assert [2] == PoolRepo.all from p in "add_col_if_not_exists_migration", select: p.to_be_added
    :ok = down(PoolRepo, num, AddColumnIfNotExistsMigration, log: false)
  end

  @tag :remove_column_if_exists
  test "remove column when exists", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, DropColumnIfExistsMigration, log: false)
    assert catch_error(PoolRepo.all from p in "drop_col_if_exists_migration", select: p.to_be_removed)
    :ok = down(PoolRepo, num, DropColumnIfExistsMigration, log: false)
  end

  @tag :on_delete_nilify_column_list
  test "nilify list of columns on_delete constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, OnDeleteNilifyColumnsMigration, log: false)

    PoolRepo.insert_all("parent", [%{col1: 1, col2: 2}])
    assert [{id, col1, col2}] = PoolRepo.all from p in "parent", select: {p.id, p.col1, p.col2}

    PoolRepo.insert_all("ref", [[parent_id: id, col1: col1, col2: col2]])
    PoolRepo.delete_all("parent")
    assert [{nil, col1, nil}] == PoolRepo.all from r in "ref", select: {r.parent_id, r.col1, r.col2}

    :ok = down(PoolRepo, num, OnDeleteNilifyColumnsMigration, log: false)
  end

  @tag :on_delete_default_all
  test "default all on_delete constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, OnDeleteDefaultAllMigration, log: false)

    PoolRepo.insert_all("parent", [%{id: 1, col1: 2, col2: 3}])
    {id, col1, col2} = {Enum.random(10..1000), Enum.random(10..1000), Enum.random(10..1000)}

    PoolRepo.insert_all("parent", [%{id: id, col1: col1, col2: col2}])
    PoolRepo.insert_all("ref", [%{parent_id: id, col1: col1, col2: col2}])
    PoolRepo.delete_all(from p in "parent", where: p.id == ^id)
    assert [{1, 2, 3}] == PoolRepo.all from r in "ref", select: {r.parent_id, r.col1, r.col2}

    :ok = down(PoolRepo, num, OnDeleteDefaultAllMigration, log: false)
  end

  @tag :on_delete_default_column_list
  test "default list of columns on_delete constraint", %{migration_number: num} do
    assert :ok == up(PoolRepo, num, OnDeleteDefaultColumnsMigration, log: false)

    PoolRepo.insert_all("parent", [%{id: 1, col1: 20, col2: 3}])

    {id, col2} = {Enum.random(10..1000), Enum.random(10..1000)}

    PoolRepo.insert_all("parent", [%{id: id, col1: 20, col2: col2}])
    PoolRepo.insert_all("ref", [%{parent_id: id, col1: 20, col2: col2}])
    PoolRepo.delete_all(from p in "parent", where: p.id == ^id)
    assert [{1, 20, 3}] == PoolRepo.all from r in "ref", select: {r.parent_id, r.col1, r.col2}

    :ok = down(PoolRepo, num, OnDeleteDefaultColumnsMigration, log: false)
  end
end
