defmodule Ecto.Adapters.Tds do
  @moduledoc """
  Adapter module for MSSQL Server using the TDS protocol.

  ## Options

  Tds options split in different categories described
  below. All options can be given via the repository
  configuration.

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 1433)
    * `:username` - Username
    * `:password` - User password
    * `:database` - the database to connect to
    * `:pool` - The connection pool module, may be set to `Ecto.Adapters.SQL.Sandbox`
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs
    * `:show_sensitive_data_on_connection_error` - show connection data and
      configuration whenever there is an error attempting to connect to the
      database

  We also recommend developers to consult the `Tds.start_link/1` documentation
  for a complete list of all supported options for driver.

  ### Storage options

    * `:collation` - the database collation. Used during database creation but
      it is ignored later

  If you need collation other than Latin1, add `tds_encoding` as dependency to
  your project `mix.exs` file then amend `config/config.ex` by adding:

      config :tds, :text_encoder, Tds.Encoding

  This should give you extended set of most encoding. For complete list check
  `Tds.Encoding` [documentation](https://hexdocs.pm/tds_encoding).

  ### After connect flags

  After connecting to MSSQL server, TDS will check if there are any flags set in
  connection options that should affect connection session behaviour. All flags are
  MSSQL standard *SET* options. The following flags are currently supported:

    * `:set_language` - sets session language (consult stored procedure output
       `exec sp_helplanguage` for valid values)
    * `:set_datefirst` - number in range 1..7
    * `:set_dateformat` - atom, one of `:mdy | :dmy | :ymd | :ydm | :myd | :dym`
    * `:set_deadlock_priority` - atom, one of `:low | :high | :normal | -10..10`
    * `:set_lock_timeout` - number in milliseconds > 0
    * `:set_remote_proc_transactions` - atom, one of `:on | :off`
    * `:set_implicit_transactions` - atom, one of `:on | :off`
    * `:set_allow_snapshot_isolation` - atom, one of `:on | :off`
       (required if `Repo.transaction(fn -> ... end, isolation_level: :snapshot)` is used)
    * `:set_read_committed_snapshot` - atom, one of `:on | :off`

  ## Limitations

  ### UUIDs

  MSSQL server has slightly different binary storage format for UUIDs (`uniqueidentifier`).
  If you use `:binary_id`, the proper choice is made. Otherwise you must use the `Tds.Ecto.UUID`
  type. Avoid using `Ecto.UUID` since it may cause unpredictable application behaviour.

  ### SQL `Char`, `VarChar` and `Text` types

  When working with binaries and strings,there are some limitations you should be aware of:

    - Strings that should be stored in mentioned sql types must be encoded to column
      codepage (defined in collation). If collation is different than database collation,
      it is not possible to store correct value into database since the connection
      respects the database collation. Ecto does not provide way to override parameter
      codepage.

    - If you need other than Latin1 or other than your database default collation, as
      mentioned in "Storage Options" section, then manually encode strings using
      `Tds.Encoding.encode/2` into desired codepage and then tag parameter as `:binary`.
      Please be aware that queries that use this approach in where clauses can be 10x slower
      due increased logical reads in database.

    - You can't store VarChar codepoints encoded in one collation/codepage to column that
      is encoded in different collation/codepage. You will always get wrong result. This is
      not adapter or driver limitation but rather how string encoding works for single byte
      encoded strings in MSSQL server. Don't be confused if you are always seeing latin1 chars,
      they are simply in each codepoint table.

  In particular, if a field has the type `:text`, only raw binaries will be allowed.
  To avoid above limitations always use `:string` (NVarChar) type for text if possible.
  If you really need to use VarChar's column type, you can use the `Tds.Ecto.VarChar`
  Ecto type.

  ### JSON support

  Even though the adapter will convert `:map` fields into JSON back and forth,
  actual value is stored in NVarChar column.

  ### Query hints and table hints

  MSSQL supports both query hints and table hints: https://docs.microsoft.com/en-us/sql/t-sql/queries/hints-transact-sql-query

  For Ecto compatibility, the query hints must be given via the `lock` option, and they
  will be translated to MSSQL's "OPTION". If you need to pass multiple options, you
  can separate them by comma:

      from query, lock: "HASH GROUP, FAST 10"

  Table hints are specified as a list alongside a `from` or `join`:

      from query, hints: ["INDEX (IX_Employee_ManagerID)"]

  The `:migration_lock` will be treated as a table hint and defaults to "UPDLOCK".

  ### Multi Repo calls in transactions

  To avoid deadlocks in your app, we exposed `:isolation_level`  repo transaction option.
  This will tell to SQL Server Transaction Manager how to begin transaction.
  By default, if this option is omitted, isolation level is set to `:read_committed`.

  Any attempt to manually set the transaction isolation via queries, such as

      Ecto.Adapter.SQL.query("SET TRANSACTION ISOLATION LEVEL XYZ")

  will fail once explicit transaction is started using `c:Ecto.Repo.transaction/2`
  and reset back to :read_committed.

  There is `Ecto.Query.lock/3` function can help by setting it to `WITH(NOLOCK)`.
  This should allow you to do eventually consistent reads and avoid locks on given
  table if you don't need to write to database.

  NOTE: after explicit transaction ends (commit or rollback) implicit transactions
  will run as READ_COMMITTED.
  """

  use Ecto.Adapters.SQL,
    driver: :tds

  require Logger
  require Ecto.Query

  @behaviour Ecto.Adapter.Storage

  @doc false
  def autogenerate(:binary_id), do: Tds.Ecto.UUID.bingenerate()
  def autogenerate(:embed_id), do: Tds.Ecto.UUID.generate()
  def autogenerate(type), do: super(type)

  @doc false
  @impl true
  def loaders({:map, _}, type), do: [&json_decode/1, &Ecto.Type.embedded_load(type, &1, :json)]
  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Tds.Ecto.UUID, type]
  def loaders(_, type), do: [type]

  @impl true
  def dumpers({:map, _}, type), do: [&Ecto.Type.embedded_dump(type, &1, :json)]
  def dumpers(:binary_id, type), do: [type, Tds.Ecto.UUID]
  def dumpers(_, type), do: [type]

  defp bool_decode(<<0>>), do: {:ok, false}
  defp bool_decode(<<1>>), do: {:ok, true}
  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x), do: {:ok, Tds.json_library().decode!(x)}
  defp json_decode(x), do: {:ok, x}

  # Storage API
  @doc false
  @impl true
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database)

    command =
      ~s(CREATE DATABASE [#{database}])
      |> concat_if(opts[:collation], &"COLLATE=#{&1}")

    case run_query(Keyword.put(opts, :database, "master"), command) do
      {:ok, _} ->
        :ok

      {:error, %{mssql: %{number: 1801}}} ->
        {:error, :already_up}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp concat_if(content, nil, _fun), do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @doc false
  @impl true
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database)

    case run_query(Keyword.put(opts, :database, "master"), "DROP DATABASE [#{database}]") do
      {:ok, _} ->
        :ok

      {:error, %{mssql: %{number: 3701}}} ->
        {:error, :already_down}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @impl Ecto.Adapter.Storage
  def storage_status(opts) do
    database = Keyword.fetch!(opts, :database)

    opts = Keyword.put(opts, :database, "master")

    check_database_query =
      "SELECT [name] FROM [master].[sys].[databases] WHERE [name] = '#{database}'"

    case run_query(opts, check_database_query) do
      {:ok, %{num_rows: 0}} -> :down
      {:ok, %{num_rows: _}} -> :up
      other -> {:error, other}
    end
  end

  defp run_query(opts, sql_command) do
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:tds)

    timeout = Keyword.get(opts, :timeout, 15_000)

    opts =
      opts
      |> Keyword.drop([:name, :log, :pool, :pool_size])
      |> Keyword.put(:backoff_type, :stop)
      |> Keyword.put(:max_restarts, 0)

    {:ok, pid} = Task.Supervisor.start_link()

    task =
      Task.Supervisor.async_nolink(pid, fn ->
        {:ok, conn} = Tds.start_link(opts)
        value = Ecto.Adapters.Tds.Connection.execute(conn, sql_command, [], opts)
        GenServer.stop(conn)
        value
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, error}} ->
        {:error, error}

      {:exit, {%{__struct__: struct} = error, _}}
      when struct in [Tds.Error, DBConnection.Error] ->
        {:error, error}

      {:exit, reason} ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}

      nil ->
        {:error, RuntimeError.exception("command timed out")}
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

    {:ok, result} =
      transaction(meta, opts, fn ->
        query =
          "exec sp_getapplock @Resource = 'ecto_#{inspect(repo)}', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = -1"

        Ecto.Adapters.SQL.query!(meta, query, [], opts)
        fun.()
      end)

    result
  end
end
