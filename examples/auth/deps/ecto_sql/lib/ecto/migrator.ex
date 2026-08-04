defmodule Ecto.Migrator do
  @moduledoc """
  Lower level API for managing migrations.

  EctoSQL provides three mix tasks for running and managing migrations:

    * `mix ecto.migrate` - migrates a repository
    * `mix ecto.rollback` - rolls back a particular migration
    * `mix ecto.migrations` - shows all migrations and their status

  Those tasks are built on top of the functions in this module.
  While the tasks above cover most use cases, it may be necessary
  from time to time to jump into the lower level API. For example,
  if you are assembling an Elixir release, Mix is not available,
  so this module provides a nice complement to still migrate your
  system.

  To learn more about migrations in general, see `Ecto.Migration`.

  ## Example: Running an individual migration

  Imagine you have this migration:

      defmodule MyApp.MigrationExample do
        use Ecto.Migration

        def up do
          execute "CREATE TABLE users(id serial PRIMARY_KEY, username text)"
        end

        def down do
          execute "DROP TABLE users"
        end
      end

  You can execute it manually with:

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)

  ## Example: Running migrations in a release

  Elixir v1.9 introduces `mix release`, which generates a self-contained
  directory that consists of your application code, all of its dependencies,
  plus the whole Erlang Virtual Machine (VM) and runtime.

  When a release is assembled, Mix is no longer available inside a release
  and therefore none of the Mix tasks. Users may still need a mechanism to
  migrate their databases. This can be achieved with using the `Ecto.Migrator`
  module:

      defmodule MyApp.Release do
        @app :my_app

        def migrate do
          for repo <- repos() do
            {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
          end
        end

        def rollback(repo, version) do
          {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
        end

        defp repos do
          Application.load(@app)
          Application.fetch_env!(@app, :ecto_repos)
        end
      end

  The example above uses `with_repo/3` to make sure the repository is
  started and then runs all migrations up or a given migration down.
  Note you will have to replace `MyApp` and `:my_app` on the first two
  lines by your actual application name. Once the file above is added
  to your application, you can assemble a new release and invoke the
  commands above in the release root like this:

      $ bin/my_app eval "MyApp.Release.migrate"
      $ bin/my_app eval "MyApp.Release.rollback(MyApp.Repo, 20190417140000)"

  ## Example: Running migrations on application startup

  Add the following to the top of your application children spec:

      {Ecto.Migrator,
       repos: Application.fetch_env!(:my_app, :ecto_repos),
       skip: System.get_env("SKIP_MIGRATIONS") == "true"}

  To skip migrations you can also pass `skip: true` or as in the example
  set the environment variable `SKIP_MIGRATIONS` to a truthy value.

  And all other options described in `up/4` are allowed,
  for example if you want to log the SQL commands,
  and run migrations in a prefix:

      {Ecto.Migrator,
       repos: Application.fetch_env!(:my_app, :ecto_repos),
       log_migrator_sql: true,
       prefix: "my_app"}

  To roll back you'd do it normally:

      $ mix ecto.rollback

  """

  require Logger
  require Ecto.Query

  alias Ecto.Migration.Runner
  alias Ecto.Migration.SchemaMigration

  @doc """
  Ensures the repo is started to perform migration operations.

  All of the application required to run the repo will be started
  before hand with chosen mode. If the repo has not yet been started,
  it is manually started, with a `:pool_size` of 2, before the given
  function is executed, and the repo is then terminated. If the repo
  was already started, then the function is directly executed, without
  terminating the repo afterwards.

  Although this function was designed to start repositories for running
  migrations, it can be used by any code, Mix task, or release tooling
  that needs to briefly start a repository to perform a certain operation
  and then terminate.

  The repo may also configure a `:start_apps_before_migration` option
  which is a list of applications to be started before the migration
  runs.

  It returns `{:ok, fun_return, apps}`, with all apps that have been
  started, or `{:error, term}`.

  ## Options

    * `:pool_size` - The pool size to start the repo for migrations.
      Defaults to 2.
    * `:mode` - The mode to start all applications.
      Defaults to `:permanent`.

  ## Examples

      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          Ecto.Migrator.run(repo, :up, all: true)
        end)

  """
  def with_repo(repo, fun, opts \\ []) do
    config = repo.config()
    mode = Keyword.get(opts, :mode, :permanent)
    apps = [:ecto_sql | config[:start_apps_before_migration] || []]

    extra_started =
      Enum.flat_map(apps, fn app ->
        {:ok, started} = Application.ensure_all_started(app, mode)
        started
      end)

    {:ok, repo_started} = repo.__adapter__().ensure_all_started(config, mode)
    started = extra_started ++ repo_started
    pool_size = Keyword.get(opts, :pool_size, 2)
    migration_repo = config[:migration_repo] || repo

    case ensure_repo_started(repo, pool_size) do
      {:ok, repo_after} ->
        case ensure_migration_repo_started(migration_repo, repo) do
          {:ok, migration_repo_after} ->
            try do
              {:ok, fun.(repo), started}
            after
              after_action(repo, repo_after)
              after_action(migration_repo, migration_repo_after)
            end

          {:error, _} = error ->
            after_action(repo, repo_after)
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets the migrations path from a repository.

  This function accepts an optional second parameter to customize the
  migrations directory. This can be used to specify a custom migrations
  path.
  """
  @spec migrations_path(Ecto.Repo.t(), String.t()) :: String.t()
  def migrations_path(repo, directory \\ "migrations") do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"
    app = Keyword.fetch!(config, :otp_app)
    Application.app_dir(app, Path.join(priv, directory))
  end

  @doc """
  Gets all migrated versions.

  This function ensures the migration table exists
  if no table has been defined yet.

  ## Options

    * `:prefix` - the prefix to run the migrations on
    * `:dynamic_repo` - the name of the Repo supervisor process.
      See `c:Ecto.Repo.put_dynamic_repo/1`.
    * `:skip_table_creation` - skips any attempt to create the migration table
      Useful for situations where user needs to check migrations but has
      insufficient permissions to create the table.  Note that migrations
      commands may fail if this is set to true. Defaults to `false`.  Accepts a
      boolean.
  """
  @spec migrated_versions(Ecto.Repo.t(), Keyword.t()) :: [integer]
  def migrated_versions(repo, opts \\ []) do
    lock_for_migrations(true, repo, opts, fn _config, versions -> versions end)
  end

  @doc """
  Runs an up migration on the given repository.

  ## Options

    * `:log` - the level to use for logging of migration instructions.
      Defaults to `:info`. Can be any of `Logger.level/0` values or a boolean.
      If `false`, it also avoids logging messages from the database.
    * `:log_migrations_sql` - the level to use for logging of SQL commands
      generated by migrations. Can be any of the `Logger.level/0` values
      or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:log_migrator_sql` - the level to use for logging of SQL commands emitted
      by the migrator, such as transactions, locks, etc. Can be any of the `Logger.level/0`
      values or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:prefix` - the prefix to run the migrations on
    * `:dynamic_repo` - the name of the Repo supervisor process.
      See `c:Ecto.Repo.put_dynamic_repo/1`.
    * `:strict_version_order` - abort when applying a migration with old timestamp
      (otherwise it emits a warning)
  """
  @spec up(Ecto.Repo.t(), integer, module, Keyword.t()) :: :ok | :already_up
  def up(repo, version, module, opts \\ []) do
    conditional_lock_for_migrations(module, version, repo, opts, fn config, versions ->
      if version in versions do
        :already_up
      else
        result = do_up(repo, config, version, module, opts)

        if version != Enum.max([version | versions]) do
          latest = Enum.max(versions)

          message = """
          You are running migration #{version} but an older \
          migration with version #{latest} has already run.

          This can be an issue if you have already ran #{latest} in production \
          because a new deployment may migrate #{version} but a rollback command \
          would revert #{latest} instead of #{version}.

          If this can be an issue, we recommend to rollback #{version} and change \
          it to a version later than #{latest}.
          """

          if opts[:strict_version_order] do
            raise Ecto.MigrationError, message
          else
            Logger.warning(message)
          end
        end

        result
      end
    end)
  end

  defp do_up(repo, config, version, module, opts) do
    async_migrate_maybe_in_transaction(repo, config, version, module, :up, opts, fn ->
      attempt(repo, config, version, module, :forward, :up, :up, opts) ||
        attempt(repo, config, version, module, :forward, :change, :up, opts) ||
        {:error,
         Ecto.MigrationError.exception(
           "#{inspect(module)} does not implement a `up/0` or `change/0` function"
         )}
    end)
  end

  @doc """
  Runs a down migration on the given repository.

  ## Options

    * `:log` - the level to use for logging of migration commands. Defaults to `:info`.
      Can be any of `Logger.level/0` values or a boolean.
    * `:log_migrations_sql` - the level to use for logging of SQL commands
      generated by migrations. Can be any of the `Logger.level/0` values
      or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:log_migrator_sql` - the level to use for logging of SQL commands emitted
      by the migrator, such as transactions, locks, etc. Can be any of the `Logger.level/0`
      values or a boolean. If `false`, logging is disabled. If `true`, uses the configured
      Repo logger level. Defaults to `false`
    * `:prefix` - the prefix to run the migrations on
    * `:dynamic_repo` - the name of the Repo supervisor process.
      See `c:Ecto.Repo.put_dynamic_repo/1`.

  """
  @spec down(Ecto.Repo.t(), integer, module) :: :ok | :already_down
  def down(repo, version, module, opts \\ []) do
    conditional_lock_for_migrations(module, version, repo, opts, fn config, versions ->
      if version in versions do
        do_down(repo, config, version, module, opts)
      else
        :already_down
      end
    end)
  end

  defp do_down(repo, config, version, module, opts) do
    async_migrate_maybe_in_transaction(repo, config, version, module, :down, opts, fn ->
      attempt(repo, config, version, module, :forward, :down, :down, opts) ||
        attempt(repo, config, version, module, :backward, :change, :down, opts) ||
        {:error,
         Ecto.MigrationError.exception(
           "#{inspect(module)} does not implement a `down/0` or `change/0` function"
         )}
    end)
  end

  defp async_migrate_maybe_in_transaction(repo, config, version, module, direction, opts, fun) do
    dynamic_repo = repo.get_dynamic_repo()

    fun_with_status = fn ->
      result = fun.()
      apply(SchemaMigration, direction, [repo, config, version, opts])
      result
    end

    fn -> run_maybe_in_transaction(repo, dynamic_repo, module, fun_with_status, opts) end
    |> Task.async()
    |> Task.await(:infinity)
  end

  defp run_maybe_in_transaction(repo, dynamic_repo, module, fun, opts) do
    repo.put_dynamic_repo(dynamic_repo)

    if module.__migration__()[:disable_ddl_transaction] ||
         not repo.__adapter__().supports_ddl_transaction?() do
      fun.()
    else
      {:ok, result} = repo.transaction(fun, log: migrator_log(opts), timeout: :infinity)

      result
    end
  catch
    kind, reason ->
      {kind, reason, __STACKTRACE__}
  end

  defp attempt(repo, config, version, module, direction, operation, reference, opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, operation, 0) do
      Runner.run(repo, config, version, module, direction, operation, reference, opts)
      :ok
    end
  end

  @doc """
  Runs migrations for the given repository.

  Equivalent to:

      Ecto.Migrator.run(repo, [Ecto.Migrator.migrations_path(repo)], direction, opts)

  See `run/4` for more information.
  """
  @spec run(Ecto.Repo.t(), atom, Keyword.t()) :: [integer]
  def run(repo, direction, opts) do
    run(repo, [migrations_path(repo)], direction, opts)
  end

  @doc ~S"""
  Apply migrations to a repository with a given strategy.

  The second argument identifies where the migrations are sourced from.
  A binary representing directory (or a list of binaries representing
  directories) may be passed, in which case we will load all files
  following the "#{VERSION}_#{NAME}.exs" schema. The `migration_source`
  may also be a list of tuples that identify the version number and
  migration modules to be run, for example:

      Ecto.Migrator.run(Repo, [{0, MyApp.Migration1}, {1, MyApp.Migration2}, ...], :up, opts)

  A strategy (which is one of `:all`, `:step`, `:to`, or `:to_exclusive`) must be given as
  an option.

  ## Execution model

  In order to run migrations, at least two database connections are
  necessary. One is used to lock the "schema_migrations" table and
  the other one to effectively run the migrations. This allows multiple
  nodes to run migrations at the same time, but guarantee that only one
  of them will effectively migrate the database.

  A downside of this approach is that migrations cannot run dynamically
  during test under the `Ecto.Adapters.SQL.Sandbox`, as the sandbox has
  to share a single connection across processes to guarantee the changes
  can be reverted.

  ## Options

    * `:all` - runs all available if `true`

    * `:step` - runs the specific number of migrations

    * `:to` - runs all until the supplied version is reached
      (including the version given in `:to`)

    * `:to_exclusive` - runs all until the supplied version is reached
      (excluding the version given in `:to_exclusive`)

  Plus all other options described in `up/4`.
  """
  @spec run(Ecto.Repo.t(), String.t() | [String.t()] | [{integer, module}], atom, Keyword.t()) ::
          [integer]
  def run(repo, migration_source, direction, opts) do
    migration_source = List.wrap(migration_source)

    pending =
      lock_for_migrations(true, repo, opts, fn _config, versions ->
        cond do
          opts[:all] ->
            pending_all(versions, migration_source, direction)

          to = opts[:to] ->
            pending_to(versions, migration_source, direction, to)

          to_exclusive = opts[:to_exclusive] ->
            pending_to_exclusive(versions, migration_source, direction, to_exclusive)

          step = opts[:step] ->
            pending_step(versions, migration_source, direction, step)

          true ->
            {:error,
             ArgumentError.exception(
               "expected one of :all, :to, :to_exclusive, or :step strategies"
             )}
        end
      end)

    # The lock above already created the table, so we can now skip it.
    opts = Keyword.put(opts, :skip_table_creation, true)

    ensure_no_duplication!(pending)
    migrate(Enum.map(pending, &load_migration!/1), direction, repo, opts)
  end

  @doc """
  Returns an array of tuples as the migration status of the given repo,
  without actually running any migrations.

  Equivalent to:

      Ecto.Migrator.migrations(repo, [Ecto.Migrator.migrations_path(repo)])

  """
  @spec migrations(Ecto.Repo.t()) :: [{:up | :down, id :: integer(), name :: String.t()}]
  def migrations(repo) do
    migrations(repo, [migrations_path(repo)])
  end

  @doc """
  Returns an array of tuples as the migration status of the given repo,
  without actually running any migrations.
  """
  @spec migrations(Ecto.Repo.t(), String.t() | [String.t()], Keyword.t()) ::
          [{:up | :down, id :: integer(), name :: String.t()}]
  def migrations(repo, directories, opts \\ []) do
    directories = List.wrap(directories)

    repo
    |> migrated_versions(opts)
    |> collect_migrations(directories)
    |> Enum.sort_by(fn {_, version, _} -> version end)
  end

  use GenServer

  @doc """
  Runs migrations as part of your supervision tree.

  ## Options

    * `:repos` - Required option to tell the migrator which Repo's to
      migrate. Example: `repos: [MyApp.Repo]`

    * `:skip` - Option to skip migrations. Defaults to `false`.

  Plus all other options described in `up/4`.

  See "Example: Running migrations on application startup" for more info.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    {repos, opts} = Keyword.pop!(opts, :repos)
    {skip?, opts} = Keyword.pop(opts, :skip, false)
    {migrator, opts} = Keyword.pop(opts, :migrator, &Ecto.Migrator.run/3)
    opts = Keyword.put(opts, :all, true)

    unless skip? do
      for repo <- repos do
        {:ok, _, _} = with_repo(repo, &migrator.(&1, :up, opts))
      end
    end

    :ignore
  end

  defp collect_migrations(versions, migration_source) do
    ups_with_file =
      versions
      |> pending_in_direction(migration_source, :down)
      |> Enum.map(fn {version, name, _} -> {:up, version, name} end)

    ups_without_file =
      versions
      |> versions_without_file(migration_source)
      |> Enum.map(fn version -> {:up, version, "** FILE NOT FOUND **"} end)

    downs =
      versions
      |> pending_in_direction(migration_source, :up)
      |> Enum.map(fn {version, name, _} -> {:down, version, name} end)

    ups_with_file ++ ups_without_file ++ downs
  end

  defp versions_without_file(versions, migration_source) do
    versions_with_file =
      migration_source
      |> migrations_for()
      |> Enum.map(fn {version, _, _} -> version end)

    versions -- versions_with_file
  end

  defp lock_for_migrations(lock_or_migration_number, repo, opts, fun) do
    dynamic_repo = Keyword.get(opts, :dynamic_repo, repo.get_dynamic_repo())
    skip_table_creation = Keyword.get(opts, :skip_table_creation, false)
    previous_dynamic_repo = repo.put_dynamic_repo(dynamic_repo)

    try do
      config = repo.config()

      unless skip_table_creation do
        verbose_schema_migration(repo, "create schema migrations table", fn ->
          SchemaMigration.ensure_schema_migrations_table!(repo, config, opts)
        end)
      end

      {migration_repo, query, all_opts} = SchemaMigration.versions(repo, config, opts[:prefix])

      migration_lock? =
        Keyword.get(opts, :migration_lock, Keyword.get(config, :migration_lock, true))

      opts =
        opts
        |> Keyword.put(:migration_source, config[:migration_source] || "schema_migrations")
        |> Keyword.put(:log, migrator_log(opts))

      result =
        if lock_or_migration_number && migration_lock? do
          # If there is a migration_repo, it wins over dynamic_repo,
          # otherwise the dynamic_repo is the one locked in migrations.
          meta_repo = if migration_repo != repo, do: migration_repo, else: dynamic_repo
          meta = Ecto.Adapter.lookup_meta(meta_repo)

          migration_repo.__adapter__().lock_for_migrations(meta, opts, fn ->
            fun.(config, migration_repo.all(query, all_opts))
          end)
        else
          fun.(config, migration_repo.all(query, all_opts))
        end

      case result do
        {kind, reason, stacktrace} ->
          :erlang.raise(kind, reason, stacktrace)

        {:error, error} ->
          raise error

        result ->
          result
      end
    after
      repo.put_dynamic_repo(previous_dynamic_repo)
    end
  end

  defp conditional_lock_for_migrations(module, version, repo, opts, fun) do
    lock = if module.__migration__()[:disable_migration_lock], do: false, else: version
    lock_for_migrations(lock, repo, opts, fun)
  end

  defp pending_to(versions, migration_source, direction, target) when is_integer(target) do
    within_target_version? = fn
      {version, _, _}, target, :up ->
        version <= target

      {version, _, _}, target, :down ->
        version >= target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&within_target_version?.(&1, target, direction))
  end

  defp pending_to_exclusive(versions, migration_source, direction, target)
       when is_integer(target) do
    within_target_version? = fn
      {version, _, _}, target, :up ->
        version < target

      {version, _, _}, target, :down ->
        version > target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&within_target_version?.(&1, target, direction))
  end

  defp pending_step(versions, migration_source, direction, count) do
    pending_in_direction(versions, migration_source, direction)
    |> Enum.take(count)
  end

  defp pending_all(versions, migration_source, direction) do
    pending_in_direction(versions, migration_source, direction)
  end

  defp pending_in_direction(versions, migration_source, :up) do
    migration_source
    |> migrations_for()
    |> Enum.filter(fn {version, _name, _file} -> version not in versions end)
  end

  defp pending_in_direction(versions, migration_source, :down) do
    migration_source
    |> migrations_for()
    |> Enum.filter(fn {version, _name, _file} -> version in versions end)
    |> Enum.reverse()
  end

  defp migrations_for(migration_source) when is_list(migration_source) do
    migration_source
    |> Enum.flat_map(fn
      directory when is_binary(directory) ->
        Path.join([directory, "**", "*.{ex,exs}"])
        |> Path.wildcard()
        |> Enum.map(&extract_migration_info/1)
        |> Enum.filter(& &1)

      {version, module} ->
        [{version, module, module}]
    end)
    |> Enum.sort()
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} ->
        if Path.extname(base) == ".ex" do
          # See: https://github.com/elixir-ecto/ecto_sql/issues/599
          IO.warn(
            """
            file looks like a migration but ends in .ex. \
            Migration files should end in .exs. Use "mix ecto.gen.migration" to generate \
            migration files with the correct extension.\
            """,
            stacktrace_info(file: file)
          )

          nil
        else
          {integer, name, file}
        end

      _ ->
        nil
    end
  end

  # TODO: Remove when we require Elixir 1.14
  if Version.match?(System.version(), ">= 1.14.0") do
    defp stacktrace_info(info), do: info
  else
    defp stacktrace_info(_info), do: []
  end

  defp ensure_no_duplication!([{version, name, _} | t]) do
    cond do
      List.keyfind(t, version, 0) ->
        raise Ecto.MigrationError,
              "migrations can't be executed, migration version #{version} is duplicated"

      List.keyfind(t, name, 1) ->
        raise Ecto.MigrationError,
              "migrations can't be executed, migration name #{name} is duplicated"

      true ->
        ensure_no_duplication!(t)
    end
  end

  defp ensure_no_duplication!([]), do: :ok

  defp load_migration!({version, _, mod}) when is_atom(mod) do
    if migration?(mod) do
      {version, mod}
    else
      raise Ecto.MigrationError, "module #{inspect(mod)} is not an Ecto.Migration"
    end
  end

  defp load_migration!({version, _, file}) when is_binary(file) do
    loaded_modules = file |> Code.compile_file() |> Enum.map(&elem(&1, 0))

    if mod = Enum.find(loaded_modules, &migration?/1) do
      {version, mod}
    else
      raise Ecto.MigrationError,
            "file #{Path.relative_to_cwd(file)} does not define an Ecto.Migration"
    end
  end

  defp migration?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__migration__, 0)
  end

  defp migrate([], direction, _repo, opts) do
    level = Keyword.get(opts, :log, :info)
    log(level, "Migrations already #{direction}")
    []
  end

  defp migrate(migrations, direction, repo, opts) do
    for {version, mod} <- migrations,
        do_direction(direction, repo, version, mod, opts),
        do: version
  end

  defp do_direction(:up, repo, version, mod, opts) do
    conditional_lock_for_migrations(mod, version, repo, opts, fn config, versions ->
      unless version in versions do
        do_up(repo, config, version, mod, opts)
      end
    end)
  end

  defp do_direction(:down, repo, version, mod, opts) do
    conditional_lock_for_migrations(mod, version, repo, opts, fn config, versions ->
      if version in versions do
        do_down(repo, config, version, mod, opts)
      end
    end)
  end

  defp verbose_schema_migration(repo, reason, fun) do
    try do
      fun.()
    rescue
      error ->
        Logger.error("""
        Could not #{reason}. This error usually happens due to the following:

          * The database does not exist
          * The "schema_migrations" table, which Ecto uses for managing
            migrations, was defined by another library
          * There is a deadlock while migrating (such as using concurrent
            indexes with a migration_lock)

        To fix the first issue, run "mix ecto.create" for the desired MIX_ENV.

        To address the second, you can run "mix ecto.drop" followed by
        "mix ecto.create", both for the desired MIX_ENV. Alternatively you may
        configure Ecto to use another table and/or repository for managing
        migrations:

            config #{inspect(repo.config()[:otp_app])}, #{inspect(repo)},
              migration_source: "some_other_table_for_schema_migrations",
              migration_repo: AnotherRepoForSchemaMigrations

        The full error report is shown below.
        """)

        reraise error, __STACKTRACE__
    end
  end

  defp log(false, _msg), do: :ok
  defp log(true, msg), do: Logger.info(msg)
  defp log(level, msg), do: Logger.log(level, msg)

  defp migrator_log(opts) do
    Keyword.get(opts, :log_migrator_sql, false)
  end

  defp ensure_repo_started(repo, pool_size) do
    case repo.start_link(pool_size: pool_size) do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :restart}

      {:error, _} = error ->
        error
    end
  end

  defp ensure_migration_repo_started(repo, repo) do
    {:ok, :noop}
  end

  defp ensure_migration_repo_started(migration_repo, _repo) do
    case migration_repo.start_link() do
      {:ok, _} ->
        {:ok, :stop}

      {:error, {:already_started, _pid}} ->
        {:ok, :noop}

      {:error, _} = error ->
        error
    end
  end

  defp after_action(repo, :restart) do
    if Process.whereis(repo) do
      %{pid: pid} = Ecto.Adapter.lookup_meta(repo)
      Supervisor.restart_child(repo, pid)
    end
  end

  defp after_action(repo, :stop) do
    repo.stop()
  end

  defp after_action(_repo, :noop) do
    :noop
  end
end
