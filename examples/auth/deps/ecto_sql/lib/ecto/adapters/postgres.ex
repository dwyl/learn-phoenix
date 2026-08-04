defmodule Ecto.Adapters.Postgres do
  @moduledoc """
  Adapter module for PostgreSQL.

  It uses `Postgrex` for communicating to the database.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Postgres options split in different categories described
  below. All options can be given via the repository
  configuration:

      config :your_app, YourApp.Repo,
        ...

  The `:prepare` option may be specified per operation:

      YourApp.Repo.all(Queryable, prepare: :unnamed)

  ### Migration options

    * `:migration_lock` - prevent multiple nodes from running migrations at the same
      time by obtaining a lock. The value `:table_lock` will lock migrations by wrapping
      the entire migration inside a database transaction, including inserting the
      migration version into the migration source (by default, "schema_migrations").
      You may alternatively select `:pg_advisory_lock` which has the benefit
      of allowing concurrent operations such as creating indexes. (default: `:table_lock`)

  When using the `:pg_advisory_lock` migration lock strategy and Ecto cannot obtain
  the lock due to another instance occupying the lock, Ecto will wait for 5 seconds
  and then retry infinity times. This is configurable on the repo with keys
  `:migration_advisory_lock_retry_interval_ms` and `:migration_advisory_lock_max_tries`.
  If the retries are exhausted, the migration will fail.

  Some downsides to using advisory locks is that some Postgres-compatible systems or plugins
  may not support session level locks well and therefore result in inconsistent behavior.
  For example, PgBouncer when using pool_modes other than session won't work well with
  advisory locks. CockroachDB is another system that is designed in a way that advisory
  locks don't make sense for their distributed database.

  ### Connection options

    * `:hostname` - Server hostname
    * `:socket_dir` - Connect to Postgres via UNIX sockets in the given directory
      The socket name is derived based on the port. This is the preferred method
      for configuring sockets and it takes precedence over the hostname. If you are
      connecting to a socket outside of the Postgres convention, use `:socket` instead;
    * `:socket` - Connect to Postgres via UNIX sockets in the given path.
      This option takes precedence over the `:hostname` and `:socket_dir`
    * `:username` - Username
    * `:password` - User password
    * `:port` - Server port (default: 5432)
    * `:database` - the database to connect to
    * `:maintenance_database` - Specifies the name of the database to connect to when
      creating or dropping the database. Defaults to `"postgres"`
    * `:pool` - The connection pool module, may be set to `Ecto.Adapters.SQL.Sandbox`
    * `:ssl` - Accepts a list of options to enable TLS for the client connection,
      or `false` to disable it. See the documentation for [Erlang's `ssl` module](`e:ssl:ssl`)
      for a list of options (default: false)
    * `:parameters` - Keyword list of connection parameters
    * `:connect_timeout` - The timeout for establishing new connections (default: 5000)
    * `:prepare` - How to prepare queries, either `:named` to use named queries
      or `:unnamed` to force unnamed queries (default: `:named`)
    * `:socket_options` - Specifies socket configuration
    * `:show_sensitive_data_on_connection_error` - show connection data and
      configuration whenever there is an error attempting to connect to the
      database

  The `:socket_options` are particularly useful when configuring the size
  of both send and receive buffers. For example, when Ecto starts with a
  pool of 20 connections, the memory usage may quickly grow from 20MB to
  50MB based on the operating system default values for TCP buffers. It is
  advised to stick with the operating system defaults but they can be
  tweaked if desired:

      socket_options: [recbuf: 8192, sndbuf: 8192]

  We also recommend developers to consult the `Postgrex.start_link/1`
  documentation for a complete listing of all supported options.

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
      or `:unspecified` to remove encoding parameter (alternative engine compatibility)
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification
    * `:dump_path` - where to place dumped structures
    * `:dump_prefixes` - list of prefixes that will be included in the structure dump.
      When specified, the prefixes will have their definitions dumped along with the
      data in their migration table. When it is not specified, the configured
      database has the definitions dumped from all of its schemas but only
      the data from the migration table from the `public` schema is included.
    * `:force_drop` - force the database to be dropped even
      if it has connections to it (requires PostgreSQL 13+)

  ### After connect callback

  If you want to execute a callback as soon as connection is established
  to the database, you can use the `:after_connect` configuration. For
  example, in your repository configuration you can add:

      after_connect: {Postgrex, :query!, ["SET search_path TO global_prefix", []]}

  You can also specify your own module that will receive the Postgrex
  connection as argument.

  ## Extensions

  Both PostgreSQL and its adapter for Elixir, Postgrex, support an
  extension system. If you want to use custom extensions for Postgrex
  alongside Ecto, you must define a type module with your extensions.
  Create a new file anywhere in your application with the following:

      Postgrex.Types.define(MyApp.PostgresTypes, [MyExtension.Foo, MyExtensionBar])

  Once your type module is defined, you can configure the repository to use it:

      config :my_app, MyApp.Repo, types: MyApp.PostgresTypes

  ## Unix socket connection

  You may desire to communicate with Postgres via Unix sockets.
  If your PG server is started on the same machine as your code, you could check that:

  ```bash
  % sudo grep unix_socket_directories /var/lib/postgres/data/postgresql.conf
  unix_socket_directories = '/run/postgresql'
  ```

  ```bash
  % ls -lah /run/postgresql
  итого 4,0K
  drwxr-xr-x  2 postgres postgres  80 июн  4 10:58 .
  drwxr-xr-x 35 root     root     840 июн  4 21:02 ..
  srwxrwxrwx  1 postgres postgres   0 июн  5 07:41 .s.PGSQL.5432
  -rw-------  1 postgres postgres  61 июн  5 07:41 .s.PGSQL.5432.lock
  ```

  So you have postgresql started and listening on the socket.
  Then you may use it as follows:

      config :your_app, YourApp.Repo,
        socket_dir: "/run/postgresql"
  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, driver: :postgrex

  require Logger

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Structure

  @default_maintenance_database "postgres"
  @default_prepare_opt :named

  @doc """
  All Ecto extensions for Postgrex.

  Currently Ecto does not define any of its own extensions for Postgrex.
  If this changes in a future release, you will need to call this function
  when defining your own custom extensions:

      Postgrex.Types.define(MyApp.PostgresTypes,
                            [MyExtension.Foo, MyExtensionBar] ++ Ecto.Adapters.Postgres.extensions())
  """
  def extensions do
    []
  end

  # Support arrays in place of IN
  @impl true
  def dumpers({:map, _}, type), do: [&Ecto.Type.embedded_dump(type, &1, :json)]
  def dumpers({:in, sub}, {:in, sub}), do: [{:array, sub}]
  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_, type), do: [type]

  ## Query API

  @impl Ecto.Adapter.Queryable
  def execute(adapter_meta, query_meta, query, params, opts) do
    prepare = Keyword.get(opts, :prepare, @default_prepare_opt)

    unless valid_prepare?(prepare) do
      raise ArgumentError,
            "expected option `:prepare` to be either `:named` or `:unnamed`, got: #{inspect(prepare)}"
    end

    Ecto.Adapters.SQL.execute(prepare, adapter_meta, query_meta, query, params, opts)
  end

  defp valid_prepare?(prepare) when prepare in [:named, :unnamed], do: true
  defp valid_prepare?(_), do: false

  ## Storage API

  @impl true
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database)

    encoding = if opts[:encoding] == :unspecified, do: nil, else: opts[:encoding] || "UTF8"
    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    check_existence_command = "SELECT FROM pg_database WHERE datname = '#{database}'"

    case run_query(check_existence_command, opts) do
      {:ok, %{num_rows: 1}} ->
        {:error, :already_up}

      _ ->
        create_command =
          ~s(CREATE DATABASE "#{database}")
          |> concat_if(encoding, &"ENCODING '#{&1}'")
          |> concat_if(opts[:template], &"TEMPLATE=#{&1}")
          |> concat_if(opts[:lc_ctype], &"LC_CTYPE='#{&1}'")
          |> concat_if(opts[:lc_collate], &"LC_COLLATE='#{&1}'")

        case run_query(create_command, opts) do
          {:ok, _} ->
            :ok

          {:error, %{postgres: %{code: :duplicate_database}}} ->
            {:error, :already_up}

          {:error, error} ->
            {:error, Exception.message(error)}
        end
    end
  end

  defp concat_if(content, nil, _), do: content
  defp concat_if(content, false, _), do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @impl true
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database)

    command =
      "DROP DATABASE \"#{database}\""
      |> concat_if(opts[:force_drop], fn _ -> "WITH (FORCE)" end)

    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    case run_query(command, opts) do
      {:ok, _} ->
        :ok

      {:error, %{postgres: %{code: :invalid_catalog_name}}} ->
        {:error, :already_down}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(opts) do
    database = Keyword.fetch!(opts, :database)

    maintenance_database = Keyword.get(opts, :maintenance_database, @default_maintenance_database)
    opts = Keyword.put(opts, :database, maintenance_database)

    check_database_query =
      "SELECT datname FROM pg_catalog.pg_database WHERE datname = '#{database}'"

    case run_query(check_database_query, opts) do
      {:ok, %{num_rows: 0}} -> :down
      {:ok, %{num_rows: _num_rows}} -> :up
      other -> {:error, other}
    end
  end

  @impl true
  def supports_ddl_transaction? do
    true
  end

  @impl true
  def lock_for_migrations(meta, opts, fun) do
    %{opts: adapter_opts, repo: repo} = meta

    if Keyword.fetch(adapter_opts, :pool_size) == {:ok, 1} do
      Ecto.Adapters.SQL.raise_migration_pool_size_error()
    end

    opts = Keyword.merge(opts, timeout: :infinity, telemetry_options: [schema_migration: true])
    config = repo.config()
    lock_strategy = Keyword.get(config, :migration_lock, :table_lock)
    do_lock_for_migrations(lock_strategy, meta, opts, config, fun)
  end

  defp do_lock_for_migrations(:pg_advisory_lock, meta, opts, config, fun) do
    lock = :erlang.phash2({:ecto, opts[:prefix], meta.repo})

    retry_state = %{
      retry_interval_ms: config[:migration_advisory_lock_retry_interval_ms] || 5000,
      max_tries: config[:migration_advisory_lock_max_tries] || :infinity,
      tries: 0
    }

    advisory_lock(meta, opts, lock, retry_state, fun)
  end

  defp do_lock_for_migrations(:table_lock, meta, opts, _config, fun) do
    {:ok, res} =
      transaction(meta, opts, fn ->
        # SHARE UPDATE EXCLUSIVE MODE is the first lock that locks
        # itself but still allows updates to happen, see
        # # https://www.postgresql.org/docs/9.4/explicit-locking.html
        source = Keyword.get(opts, :migration_source, "schema_migrations")
        table = if prefix = opts[:prefix], do: ~s|"#{prefix}"."#{source}"|, else: ~s|"#{source}"|
        lock_statement = "LOCK TABLE #{table} IN SHARE UPDATE EXCLUSIVE MODE"
        {:ok, _} = Ecto.Adapters.SQL.query(meta, lock_statement, [], opts)

        fun.()
      end)

    res
  end

  defp advisory_lock(meta, opts, lock, retry_state, fun) do
    result =
      checkout(meta, opts, fn ->
        case Ecto.Adapters.SQL.query(meta, "SELECT pg_try_advisory_lock(#{lock})", [], opts) do
          {:ok, %{rows: [[true]]}} ->
            try do
              {:ok, fun.()}
            after
              release_advisory_lock(meta, opts, lock)
            end

          _ ->
            :no_advisory_lock
        end
      end)

    case result do
      {:ok, fun_result} ->
        fun_result

      :no_advisory_lock ->
        maybe_retry_advisory_lock(meta, opts, lock, retry_state, fun)
    end
  end

  defp release_advisory_lock(meta, opts, lock) do
    case Ecto.Adapters.SQL.query(meta, "SELECT pg_advisory_unlock(#{lock})", [], opts) do
      {:ok, %{rows: [[true]]}} ->
        :ok

      _ ->
        raise "failed to release advisory lock"
    end
  end

  defp maybe_retry_advisory_lock(meta, opts, lock, retry_state, fun) do
    %{retry_interval_ms: interval, max_tries: max_tries, tries: tries} = retry_state

    if max_tries != :infinity && max_tries <= tries do
      raise "failed to obtain advisory lock. Tried #{max_tries} times waiting #{interval}ms between tries"
    else
      if Keyword.get(opts, :log_migrator_sql, false) do
        Logger.info(
          "Migration lock occupied for #{inspect(meta.repo)}. Retry #{tries + 1}/#{max_tries} at #{interval}ms intervals."
        )
      end

      Process.sleep(interval)
      retry_state = %{retry_state | tries: tries + 1}
      advisory_lock(meta, opts, lock, retry_state, fun)
    end
  end

  @impl true
  def structure_dump(default, config) do
    table = config[:migration_source] || "schema_migrations"

    with {:ok, versions} <- select_versions(table, config),
         {:ok, path} <- pg_dump(default, config),
         do: append_versions(table, versions, path)
  end

  defp select_versions(table, config) do
    prefixes = config[:dump_prefixes] || ["public"]

    result =
      Enum.reduce_while(prefixes, [], fn prefix, versions ->
        case run_query(~s[SELECT version FROM #{prefix}."#{table}" ORDER BY version], config) do
          {:ok, %{rows: rows}} -> {:cont, Enum.map(rows, &{prefix, hd(&1)}) ++ versions}
          {:error, %{postgres: %{code: :undefined_table}}} -> {:cont, versions}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:error, _} = error -> error
      versions -> {:ok, versions}
    end
  end

  defp pg_dump(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    prefixes = config[:dump_prefixes] || []
    non_prefix_args = ["--file", path, "--schema-only", "--no-acl", "--no-owner"]

    args =
      Enum.reduce(prefixes, non_prefix_args, fn prefix, acc ->
        ["-n", prefix | acc]
      end)

    File.mkdir_p!(Path.dirname(path))

    case run_with_cmd("pg_dump", config, args) do
      {_output, 0} ->
        {:ok, path}

      {output, _} ->
        {:error, output}
    end
  end

  defp append_versions(_table, [], path) do
    {:ok, path}
  end

  defp append_versions(table, versions, path) do
    sql =
      Enum.map_join(versions, fn {prefix, version} ->
        ~s[INSERT INTO #{prefix}."#{table}" (version) VALUES (#{version});\n]
      end)

    File.open!(path, [:append], fn file ->
      IO.write(file, sql)
    end)

    {:ok, path}
  end

  @impl true
  def structure_load(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    args = ["--quiet", "--file", path, "-vON_ERROR_STOP=1", "--single-transaction"]

    case run_with_cmd("psql", config, args) do
      {_output, 0} -> {:ok, path}
      {output, _} -> {:error, output}
    end
  end

  @impl true
  def dump_cmd(args, opts \\ [], config) when is_list(config) and is_list(args),
    do: run_with_cmd("pg_dump", config, args, opts)

  ## Helpers

  defp run_query(sql, opts) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    task =
      Task.Supervisor.async_nolink(Ecto.Adapters.SQL.StorageSupervisor, fn ->
        {:ok, conn} = Postgrex.start_link(opts)

        value = Postgrex.query(conn, sql, [], opts)
        GenServer.stop(conn)
        value
      end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, error}} ->
        {:error, error}

      {:exit, {%{__struct__: struct} = error, _}}
      when struct in [Postgrex.Error, DBConnection.Error] ->
        {:error, error}

      {:exit, reason} ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}

      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end

  defp run_with_cmd(cmd, opts, opt_args, cmd_opts \\ []) do
    unless System.find_executable(cmd) do
      raise "could not find executable `#{cmd}` in path, " <>
              "please guarantee it is available before running ecto commands"
    end

    env = [{"PGCONNECT_TIMEOUT", "10"}]

    env =
      if password = opts[:password] do
        [{"PGPASSWORD", password} | env]
      else
        env
      end

    args = []
    args = if username = opts[:username], do: ["--username", username | args], else: args
    args = if port = opts[:port], do: ["--port", to_string(port) | args], else: args
    args = if database = opts[:database], do: ["--dbname", database | args], else: args

    host = opts[:socket_dir] || opts[:hostname] || System.get_env("PGHOST") || "localhost"

    if opts[:socket] do
      IO.warn(
        ":socket option is ignored when connecting in structure_load/2 and structure_dump/2," <>
          " use :socket_dir or :hostname instead"
      )
    end

    args = ["--host", host | args]
    args = args ++ opt_args

    cmd_opts =
      cmd_opts
      |> Keyword.put_new(:stderr_to_stdout, true)
      |> Keyword.update(:env, env, &Enum.concat(env, &1))

    System.cmd(cmd, args, cmd_opts)
  end
end
