Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.MigratorTest do
  use Ecto.Integration.Case

  import Support.FileHelpers
  import ExUnit.CaptureLog
  import Ecto.Migrator

  alias Ecto.Integration.{TestRepo, PoolRepo}
  alias Ecto.Migration.SchemaMigration

  setup config do
    Process.register(self(), config.test)
    PoolRepo.delete_all(SchemaMigration)
    :ok
  end

  defmodule AnotherSchemaMigration do
    use Ecto.Migration

    def change do
      execute TestRepo.create_prefix("bad_schema_migrations"),
              TestRepo.drop_prefix("bad_schema_migrations")

      create table(:schema_migrations, prefix: "bad_schema_migrations") do
        add :version, :string
        add :inserted_at, :integer
      end
    end
  end

  defmodule BrokenLinkMigration do
    use Ecto.Migration

    def change do
      Task.start_link(fn -> raise "oops" end)
      Process.sleep(:infinity)
    end
  end

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      create table(:good_migration)
    end

    def down do
      drop table(:good_migration)
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def change do
      execute "CREATE WHAT"
    end
  end

  test "migrations up and down" do
    assert migrated_versions(PoolRepo) == []
    assert up(PoolRepo, 31, GoodMigration, log: false) == :ok

    [migration] = PoolRepo.all(SchemaMigration)
    assert migration.version == 31
    assert migration.inserted_at

    assert migrated_versions(PoolRepo) == [31]
    assert up(PoolRepo, 31, GoodMigration, log: false) == :already_up
    assert migrated_versions(PoolRepo) == [31]
    assert down(PoolRepo, 32, GoodMigration, log: false) == :already_down
    assert migrated_versions(PoolRepo) == [31]
    assert down(PoolRepo, 31, GoodMigration, log: false) == :ok
    assert migrated_versions(PoolRepo) == []
  end

  @tag :prefix
  test "does not commit migration if insert into schema migration fails" do
    # First we create a new schema migration table in another prefix
    assert up(PoolRepo, 33, AnotherSchemaMigration, log: false) == :ok
    assert migrated_versions(PoolRepo) == [33]

    catch_error(up(PoolRepo, 34, GoodMigration, log: false, prefix: "bad_schema_migrations"))
    catch_error(PoolRepo.all("good_migration"))
    catch_error(PoolRepo.all("good_migration", prefix: "bad_schema_migrations"))

    assert down(PoolRepo, 33, AnotherSchemaMigration, log: false) == :ok
  end

  test "ecto-generated migration queries pass schema_migration in telemetry options" do
    handler = fn _event_name, _measurements, metadata ->
      send(self(), metadata)
    end

    # migration table creation
    Process.put(:telemetry, handler)
    migrated_versions(PoolRepo, log: false)
    assert_received %{options: [schema_migration: true]}

    # transaction begin statement
    Process.put(:telemetry, handler)
    migrated_versions(PoolRepo, skip_table_creation: true, log: false)
    assert_received %{options: [schema_migration: true]}

    # retrieving the migration versions
    Process.put(:telemetry, handler)
    migrated_versions(PoolRepo, migration_lock: false, skip_table_creation: true, log: false)
    assert_received %{options: [schema_migration: true]}
  end

  test "bad execute migration" do
    assert catch_error(up(PoolRepo, 31, BadMigration, log: false))
    assert DynamicSupervisor.which_children(Ecto.MigratorSupervisor) == []
  end

  test "broken link migration" do
    Process.flag(:trap_exit, true)

    assert capture_log(fn ->
      {:ok, pid} = Task.start_link(fn -> up(PoolRepo, 31, BrokenLinkMigration, log: false) end)
      assert_receive {:EXIT, ^pid, _}
    end) =~ "oops"

    assert capture_log(fn ->
      catch_exit(up(PoolRepo, 31, BrokenLinkMigration, log: false))
    end) =~ "oops"
  end

  test "run up to/step migration", config do
    in_tmp fn path ->
      create_migration(47, config)
      create_migration(48, config)

      assert [47] = run(PoolRepo, path, :up, step: 1, log: false)
      assert count_entries() == 1

      assert [48] = run(PoolRepo, path, :up, to: 48, log: false)
    end
  end

  test "run down to/step migration", config do
    in_tmp fn path ->
      migrations = [
        create_migration(49, config),
        create_migration(50, config),
      ]

      assert [49, 50] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [50] = run(PoolRepo, path, :down, step: 1, log: false)
      purge migrations

      assert count_entries() == 1
      assert [50] = run(PoolRepo, path, :up, to: 50, log: false)
    end
  end

  test "runs all migrations", config do
    in_tmp fn path ->
      migrations = [
        create_migration(53, config),
        create_migration(54, config),
      ]

      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
      assert [] = run(PoolRepo, path, :up, all: true, log: false)
      purge migrations

      assert [54, 53] = run(PoolRepo, path, :down, all: true, log: false)
      purge migrations

      assert count_entries() == 0
      assert [53, 54] = run(PoolRepo, path, :up, all: true, log: false)
    end
  end

  test "does not commit half transactions on bad syntax", config do
    in_tmp fn path ->
      migrations = [
        create_migration(64, config),
        create_migration("65_+", config)
      ]

      assert_raise SyntaxError, fn ->
        run(PoolRepo, path, :up, all: true, log: false)
      end

      refute_received {:up, _}
      assert count_entries() == 0
      purge migrations
    end
  end

  @tag :lock_for_migrations
  test "raises when connection pool is too small" do
    config = Application.fetch_env!(:ecto_sql, PoolRepo)
    config = Keyword.merge(config, pool_size: 1)
    Application.put_env(:ecto_sql, __MODULE__.SingleConnectionRepo, config)

    defmodule SingleConnectionRepo do
      use Ecto.Repo, otp_app: :ecto_sql, adapter: PoolRepo.__adapter__()
    end

    {:ok, _pid} = SingleConnectionRepo.start_link()

    in_tmp fn path ->
      exception_message = ~r/Migrations failed to run because the connection pool size is less than 2/

      assert_raise Ecto.MigrationError, exception_message, fn ->
        run(SingleConnectionRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "does not raise when connection pool is too small but there is no lock" do
    config = Application.fetch_env!(:ecto_sql, PoolRepo)
    config = Keyword.merge(config, pool_size: 1, migration_lock: nil)
    Application.put_env(:ecto_sql, __MODULE__.SingleConnectionNoLockRepo, config)

    defmodule SingleConnectionNoLockRepo do
      use Ecto.Repo, otp_app: :ecto_sql, adapter: PoolRepo.__adapter__()
    end

    {:ok, _pid} = SingleConnectionNoLockRepo.start_link()

    in_tmp fn path ->
      run(SingleConnectionNoLockRepo, path, :up, all: true, log: false)
    end
  end

  defp count_entries() do
    PoolRepo.aggregate(SchemaMigration, :count, :version)
  end

  defp create_migration(num, config) do
    module = Module.concat(__MODULE__, "Migration#{num}")

    File.write! "#{num}_migration_#{num}.exs", """
    defmodule #{module} do
      use Ecto.Migration

      def up do
        send #{inspect config.test}, {:up, #{inspect num}}
      end

      def down do
        send #{inspect config.test}, {:down, #{inspect num}}
      end
    end
    """

    module
  end

  defp purge(modules) do
    Enum.each(List.wrap(modules), fn m ->
      :code.delete m
      :code.purge m
    end)
  end
end
