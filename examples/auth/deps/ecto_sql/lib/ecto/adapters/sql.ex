defmodule Ecto.Adapters.SQL do
  @moduledoc ~S"""
  This application provides functionality for working with
  SQL databases in `Ecto`.

  ## Built-in adapters

  By default, we support the following adapters:

    * `Ecto.Adapters.Postgres` for Postgres
    * `Ecto.Adapters.MyXQL` for MySQL
    * `Ecto.Adapters.Tds` for SQLServer

  ## Additional functions

  If your `Ecto.Repo` is backed by any of the SQL adapters above,
  this module will inject additional functions into your repository:

    * `disconnect_all(interval, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.disconnect_all/3`

    * `explain(type, query, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.explain/4`

    * `query(sql, params, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.query/4`

    * `query!(sql, params, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.query!/4`

    * `query_many(sql, params, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.query_many/4`

    * `query_many!(sql, params, options \\ [])` -
       shortcut for `Ecto.Adapters.SQL.query_many!/4`

    * `to_sql(type, query)` -
       shortcut for `Ecto.Adapters.SQL.to_sql/3`

  Generally speaking, you must invoke those functions directly from
  your repository, for example: `MyApp.Repo.query("SELECT true")`.
  You can also invoke them directly from `Ecto.Adapters.SQL`, but
  keep in mind that in such cases features such as "dynamic repositories"
  won't be available.

  ## Migrations

  `ecto_sql` supports database migrations. You can generate a migration
  with:

      $ mix ecto.gen.migration create_posts

  This will create a new file inside `priv/repo/migrations` with the
  `change` function. Check `Ecto.Migration` for more information.

  To interface with migrations, developers typically use mix tasks:

    * `mix ecto.migrations` - lists all available migrations and their status
    * `mix ecto.migrate` - runs a migration
    * `mix ecto.rollback` - rolls back a previously run migration

  If you want to run migrations programmatically, see `Ecto.Migrator`.

  ## SQL sandbox

  `ecto_sql` provides a sandbox for testing. The sandbox wraps each
  test in a transaction, making sure the tests are isolated and can
  run concurrently. See `Ecto.Adapters.SQL.Sandbox` for more information.

  ## Structure load and dumping

  If you have an existing database, you may want to dump its existing
  structure and make it reproducible from within Ecto. This can be
  achieved with two Mix tasks:

    * `mix ecto.load` - loads an existing structure into the database
    * `mix ecto.dump` - dumps the existing database structure to the filesystem

  For creating and dropping databases, see `mix ecto.create`
  and `mix ecto.drop` that are included as part of Ecto.

  ## Custom adapters

  Developers can implement their own SQL adapters by using
  `Ecto.Adapters.SQL` and by implementing the callbacks required
  by `Ecto.Adapters.SQL.Connection`  for handling connections and
  performing queries. The connection handling and pooling for SQL
  adapters should be built using the `DBConnection` library.

  When using `Ecto.Adapters.SQL`, the following options are required:

    * `:driver` (required) - the database driver library.
      For example: `:postgrex`

  """

  require Logger

  @type query_result :: %{
          :rows => nil | [[term] | binary],
          :num_rows => non_neg_integer,
          optional(atom) => any
        }

  @type query_params :: [term] | %{(atom | String.t()) => term}

  @doc false
  defmacro __using__(opts) do
    quote do
      @behaviour Ecto.Adapter
      @behaviour Ecto.Adapter.Migration
      @behaviour Ecto.Adapter.Queryable
      @behaviour Ecto.Adapter.Schema
      @behaviour Ecto.Adapter.Transaction

      opts = unquote(opts)
      @conn __MODULE__.Connection
      @driver Keyword.fetch!(opts, :driver)

      @impl true
      defmacro __before_compile__(env) do
        Ecto.Adapters.SQL.__before_compile__(@driver, env)
      end

      @impl true
      def ensure_all_started(config, type) do
        Ecto.Adapters.SQL.ensure_all_started(@driver, config, type)
      end

      @impl true
      def init(config) do
        Ecto.Adapters.SQL.init(@conn, @driver, config)
      end

      @impl true
      def checkout(meta, opts, fun) do
        Ecto.Adapters.SQL.checkout(meta, opts, fun)
      end

      @impl true
      def checked_out?(meta) do
        Ecto.Adapters.SQL.checked_out?(meta)
      end

      @impl true
      def loaders({:map, _}, type), do: [&Ecto.Type.embedded_load(type, &1, :json)]
      def loaders(:binary_id, type), do: [Ecto.UUID, type]
      def loaders(_, type), do: [type]

      @impl true
      def dumpers({:map, _}, type), do: [&Ecto.Type.embedded_dump(type, &1, :json)]
      def dumpers(:binary_id, type), do: [type, Ecto.UUID]
      def dumpers(_, type), do: [type]

      ## Query

      @impl true
      def prepare(:all, query) do
        {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.all(query))}}
      end

      def prepare(:update_all, query) do
        {:cache,
         {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.update_all(query))}}
      end

      def prepare(:delete_all, query) do
        {:cache,
         {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.delete_all(query))}}
      end

      @impl true
      def execute(adapter_meta, query_meta, query, params, opts) do
        Ecto.Adapters.SQL.execute(:named, adapter_meta, query_meta, query, params, opts)
      end

      @impl true
      def stream(adapter_meta, query_meta, query, params, opts) do
        Ecto.Adapters.SQL.stream(adapter_meta, query_meta, query, params, opts)
      end

      ## Schema

      @impl true
      def autogenerate(:id), do: nil
      def autogenerate(:embed_id), do: Ecto.UUID.generate()
      def autogenerate(:binary_id), do: Ecto.UUID.bingenerate()

      @impl true
      def insert_all(
            adapter_meta,
            schema_meta,
            header,
            rows,
            on_conflict,
            returning,
            placeholders,
            opts
          ) do
        Ecto.Adapters.SQL.insert_all(
          adapter_meta,
          schema_meta,
          @conn,
          header,
          rows,
          on_conflict,
          returning,
          placeholders,
          opts
        )
      end

      @impl true
      def insert(adapter_meta, schema_meta, params, on_conflict, returning, opts) do
        %{source: source, prefix: prefix} = schema_meta
        {kind, conflict_params, _} = on_conflict
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(prefix, source, fields, [fields], on_conflict, returning, [])

        Ecto.Adapters.SQL.struct(
          adapter_meta,
          @conn,
          sql,
          :insert,
          source,
          [],
          values ++ conflict_params,
          kind,
          returning,
          opts
        )
      end

      @impl true
      def update(adapter_meta, schema_meta, fields, params, returning, opts) do
        %{source: source, prefix: prefix} = schema_meta
        {fields, field_values} = :lists.unzip(fields)
        filter_values = Keyword.values(params)
        sql = @conn.update(prefix, source, fields, params, returning)

        Ecto.Adapters.SQL.struct(
          adapter_meta,
          @conn,
          sql,
          :update,
          source,
          params,
          field_values ++ filter_values,
          :raise,
          returning,
          opts
        )
      end

      @impl true
      def delete(adapter_meta, schema_meta, params, returning, opts) do
        %{source: source, prefix: prefix} = schema_meta
        filter_values = Keyword.values(params)
        sql = @conn.delete(prefix, source, params, returning)

        Ecto.Adapters.SQL.struct(
          adapter_meta,
          @conn,
          sql,
          :delete,
          source,
          params,
          filter_values,
          :raise,
          returning,
          opts
        )
      end

      ## Transaction

      @impl true
      def transaction(meta, opts, fun) do
        Ecto.Adapters.SQL.transaction(meta, opts, fun)
      end

      @impl true
      def in_transaction?(meta) do
        Ecto.Adapters.SQL.in_transaction?(meta)
      end

      @impl true
      def rollback(meta, value) do
        Ecto.Adapters.SQL.rollback(meta, value)
      end

      ## Migration

      @impl true
      def execute_ddl(meta, definition, opts) do
        Ecto.Adapters.SQL.execute_ddl(meta, @conn, definition, opts)
      end

      defoverridable prepare: 2,
                     execute: 5,
                     insert: 6,
                     update: 6,
                     delete: 5,
                     insert_all: 8,
                     execute_ddl: 3,
                     loaders: 2,
                     dumpers: 2,
                     autogenerate: 1,
                     checkout: 3,
                     ensure_all_started: 2,
                     __before_compile__: 1
    end
  end

  @timeout 15_000

  @query_doc """
  Runs a custom SQL query.

  If the query was successful, it will return an `:ok` tuple containing
  a map with at least two keys:
    * `:num_rows` - the number of rows affected
    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  ## Options
    * `:log` - When false, does not log the query
    * `:timeout` - Execute request timeout, accepts: `:infinity` (default: `#{@timeout}`);

  ## Examples
      iex> MyRepo.query("SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [[42]], num_rows: 1}}

      iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [[42]], num_rows: 1}}
  """

  @query_bang_doc """
  Same as `query/3` but returns result directly without `:ok` tuple
  and raises on invalid queries
  """

  @query_many_doc """
  Runs a custom SQL query that returns multiple results on the given repo.

  In case of success, it must return an `:ok` tuple containing a list of
  maps with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  ## Options

    * `:log` - When false, does not log the query
    * `:timeout` - Execute request timeout, accepts: `:infinity` (default: `#{@timeout}`);

  ## Examples

      iex> MyRepo.query_many("SELECT $1; SELECT $2;", [40, 2])
      {:ok, [%{rows: [[40]], num_rows: 1}, %{rows: [[2]], num_rows: 1}]}

      iex> Ecto.Adapters.SQL.query_many(MyRepo, "SELECT $1; SELECT $2;", [40, 2])
      {:ok, [%{rows: [[40]], num_rows: 1}, %{rows: [[2]], num_rows: 1}]}
  """

  @query_many_bang_doc """
  Same as `query_many/4` but returns result directly without `:ok` tuple
  and raises on invalid queries
  """

  @to_sql_doc """
  Converts the given query to SQL according to its kind and the
  adapter in the given repository.

  ## Examples

  The examples below are meant for reference. Each adapter will
  return a different result:

      iex> MyRepo.to_sql(:all, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

      iex> MyRepo.to_sql(:update_all, from(p in Post, update: [set: [title: ^"hello"]]))
      {"UPDATE posts AS p SET title = $1", ["hello"]}

      iex> Ecto.Adapters.SQL.to_sql(:all, MyRepo, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}
  """

  @explain_doc """
  Executes an EXPLAIN statement or similar for the given query according to its kind and the
  adapter in the given repository.

  ## Examples

      # Postgres
      iex> MyRepo.explain(:all, Post)
      "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)"

      iex> Ecto.Adapters.SQL.explain(Repo, :all, Post)
      "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)"

      # MySQL
      iex> MyRepo.explain(:all, from(p in Post, where: p.title == "title")) |> IO.puts()
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
      | id | select_type | table | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+
      |  1 | SIMPLE      | p0    | NULL       | ALL  | NULL          | NULL | NULL    | NULL |    1 |    100.0 | Using where |
      +----+-------------+-------+------------+------+---------------+------+---------+------+------+----------+-------------+

      # Shared opts
      iex> MyRepo.explain(:all, Post, analyze: true, timeout: 20_000)
      "Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=443) (actual time=0.013..0.013 rows=0 loops=1)\\nPlanning Time: 0.031 ms\\nExecution Time: 0.021 ms"

  It's safe to execute it for updates and deletes, no data change will be committed:

      iex> MyRepo.explain(Repo, :update_all, from(p in Post, update: [set: [title: "new title"]]))
      "Update on posts p0  (cost=0.00..11.70 rows=170 width=449)\\n  ->  Seq Scan on posts p0  (cost=0.00..11.70 rows=170 width=449)"

  This function is also available under the repository with name `explain`:

      iex> MyRepo.explain(:all, from(p in Post, where: p.title == "title"))
      "Seq Scan on posts p0  (cost=0.00..12.12 rows=1 width=443)\\n  Filter: ((title)::text = 'title'::text)"

  ### Options

  Built-in adapters support passing `opts` to the EXPLAIN statement according to the following:

  Adapter          | Supported opts
  ---------------- | --------------
  Postgrex         | `analyze`, `verbose`, `costs`, `settings`, `buffers`, `timing`, `summary`, `format`, `plan`
  MyXQL            | `format`

  All options except `format` are boolean valued and default to `false`.

  The allowed `format` values are `:map`, `:yaml`, and `:text`:
    * `:map` is the deserialized JSON encoding.
    * `:yaml` and `:text` return the result as a string.

  The built-in adapters support the following formats:
    * Postgrex: `:map`, `:yaml` and `:text`
    * MyXQL: `:map` and `:text`

  The `:plan` option in Postgrex can take the values `:custom` or `:fallback_generic`. When `:custom`
  is specified, the explain plan generated will consider the specific values of the query parameters
  that are supplied. When using `:fallback_generic`, the specific values of the query parameters will
  be ignored. `:fallback_generic` does not use PostgreSQL's built-in support for a generic explain
  plan (available as of PostgreSQL 16), but instead uses a special implementation that works for PostgreSQL
  versions 12 and above. Defaults to `:custom`.

  Any other value passed to `opts` will be forwarded to the underlying adapter query function, including
  shared Repo options such as `:timeout`. Non built-in adapters may have specific behaviour and you should
  consult their documentation for more details.

  For version compatibility, please check your database's documentation:

    * _Postgrex_: [PostgreSQL doc](https://www.postgresql.org/docs/current/sql-explain.html).
    * _MyXQL_: [MySQL doc](https://dev.mysql.com/doc/refman/8.0/en/explain.html).

  """

  @disconnect_all_doc """
  Forces all connections in the repo pool to disconnect within the given interval.

  Once this function is called, the pool will disconnect all of its connections
  as they are checked in or as they are pinged. Checked in connections will be
  randomly disconnected within the given time interval. Pinged connections are
  immediately disconnected - as they are idle (according to `:idle_interval`).

  If the connection has a backoff configured (which is the case by default),
  disconnecting means an attempt at a new connection will be done immediately
  after, without starting a new process for each connection. However, if backoff
  has been disabled, the connection process will terminate. In such cases,
  disconnecting all connections may cause the pool supervisor to restart
  depending on the max_restarts/max_seconds configuration of the pool,
  so you will want to set those carefully.
  """

  @doc @to_sql_doc
  @spec to_sql(:all | :update_all | :delete_all, Ecto.Repo.t(), Ecto.Queryable.t()) ::
          {String.t(), query_params}
  def to_sql(kind, repo, queryable) do
    case Ecto.Adapter.Queryable.prepare_query(kind, repo, queryable) do
      {{:cached, _update, _reset, {_id, cached}}, params} ->
        {String.Chars.to_string(cached), params}

      {{:cache, _update, {_id, prepared}}, params} ->
        {prepared, params}

      {{:nocache, {_id, prepared}}, params} ->
        {prepared, params}
    end
  end

  @doc @explain_doc
  @spec explain(
          pid() | Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          :all | :update_all | :delete_all,
          Ecto.Queryable.t(),
          opts :: Keyword.t()
        ) :: String.t() | Exception.t() | list(map)
  def explain(repo, operation, queryable, opts \\ [])

  def explain(repo, operation, queryable, opts) when is_atom(repo) or is_pid(repo) do
    explain(Ecto.Adapter.lookup_meta(repo), operation, queryable, opts)
  end

  def explain(%{repo: repo} = adapter_meta, operation, queryable, opts) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:explain, fn _, _ ->
      {prepared, prepared_params} = to_sql(operation, repo, queryable)
      sql_call(adapter_meta, :explain_query, [prepared], prepared_params, opts)
    end)
    |> Ecto.Multi.run(:rollback, fn _, _ ->
      {:error, :forced_rollback}
    end)
    |> repo.transaction(opts)
    |> case do
      {:error, :rollback, :forced_rollback, %{explain: result}} -> result
      {:error, :explain, error, _} -> raise error
      _ -> raise "unable to execute explain"
    end
  end

  @doc @disconnect_all_doc
  @spec disconnect_all(
          pid | Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          non_neg_integer,
          opts :: Keyword.t()
        ) :: :ok
  def disconnect_all(repo, interval, opts \\ [])

  def disconnect_all(repo, interval, opts) when is_atom(repo) or is_pid(repo) do
    disconnect_all(Ecto.Adapter.lookup_meta(repo), interval, opts)
  end

  def disconnect_all(adapter_meta, interval, opts) do
    case adapter_meta do
      %{partition_supervisor: {name, count}} ->
        1..count
        |> Enum.map(fn i ->
          Task.async(fn ->
            DBConnection.disconnect_all({:via, PartitionSupervisor, {name, i}}, interval, opts)
          end)
        end)
        |> Task.await_many(:infinity)

        :ok

      %{pid: pool} ->
        DBConnection.disconnect_all(pool, interval, opts)
    end
  end

  @doc """
  Returns a stream that runs a custom SQL query on given repo when reduced.

  In case of success it is a enumerable containing maps with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  In case of failure it raises an exception.

  If the adapter supports a collectable stream, the stream may also be used as
  the collectable in `Enum.into/3`. Behaviour depends on the adapter.

  ## Options

    * `:log` - When false, does not log the query
    * `:max_rows` - The number of rows to load from the database as we stream

  ## Examples

      iex> Ecto.Adapters.SQL.stream(MyRepo, "SELECT $1::integer + $2", [40, 2]) |> Enum.to_list()
      [%{rows: [[42]], num_rows: 1}]

  """
  @spec stream(Ecto.Repo.t(), String.t(), query_params, Keyword.t()) :: Enum.t()
  def stream(repo, sql, params \\ [], opts \\ []) do
    repo
    |> Ecto.Adapter.lookup_meta()
    |> Ecto.Adapters.SQL.Stream.build(sql, params, opts)
  end

  @doc @query_bang_doc
  @spec query!(
          pid() | Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          iodata,
          query_params,
          Keyword.t()
        ) ::
          query_result
  def query!(repo, sql, params \\ [], opts \\ []) do
    case query(repo, sql, params, opts) do
      {:ok, result} -> result
      {:error, err} -> raise_sql_call_error(err)
    end
  end

  @doc @query_doc
  @spec query(
          pid() | Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          iodata,
          query_params,
          Keyword.t()
        ) ::
          {:ok, query_result} | {:error, Exception.t()}
  def query(repo, sql, params \\ [], opts \\ [])

  def query(repo, sql, params, opts) when is_atom(repo) or is_pid(repo) do
    query(Ecto.Adapter.lookup_meta(repo), sql, params, opts)
  end

  def query(adapter_meta, sql, params, opts) do
    sql_call(adapter_meta, :query, [sql], params, opts)
  end

  @doc @query_many_bang_doc
  @spec query_many!(
          Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          iodata,
          query_params,
          Keyword.t()
        ) ::
          [query_result]
  def query_many!(repo, sql, params \\ [], opts \\ []) do
    case query_many(repo, sql, params, opts) do
      {:ok, result} -> result
      {:error, err} -> raise_sql_call_error(err)
    end
  end

  @doc @query_many_doc
  @spec query_many(
          pid() | Ecto.Repo.t() | Ecto.Adapter.adapter_meta(),
          iodata,
          query_params,
          Keyword.t()
        ) :: {:ok, [query_result]} | {:error, Exception.t()}
  def query_many(repo, sql, params \\ [], opts \\ [])

  def query_many(repo, sql, params, opts) when is_atom(repo) or is_pid(repo) do
    query_many(Ecto.Adapter.lookup_meta(repo), sql, params, opts)
  end

  def query_many(adapter_meta, sql, params, opts) do
    sql_call(adapter_meta, :query_many, [sql], params, opts)
  end

  defp sql_call(adapter_meta, callback, args, params, opts) do
    %{
      pid: pool,
      telemetry: telemetry,
      sql: sql,
      opts: default_opts,
      log_stacktrace_mfa: log_stacktrace_mfa
    } = adapter_meta

    conn = get_conn_or_pool(pool, adapter_meta)
    opts = with_log(telemetry, log_stacktrace_mfa, params, opts ++ default_opts)
    args = args ++ [params, opts]
    apply(sql, callback, [conn | args])
  end

  defp put_source(opts, %{sources: sources}) when is_binary(elem(elem(sources, 0), 0)) do
    {source, _, _} = elem(sources, 0)
    [source: source] ++ opts
  end

  defp put_source(opts, _) do
    opts
  end

  @doc """
  Checks if the given `table` exists.

  Returns `true` if the `table` exists in the `repo`, otherwise `false`.
  The table is checked against the current database/schema in the connection.
  """
  @spec table_exists?(Ecto.Repo.t(), table :: String.t(), opts :: Keyword.t()) :: boolean
  def table_exists?(repo, table, opts \\ []) when is_atom(repo) do
    %{sql: sql} = adapter_meta = Ecto.Adapter.lookup_meta(repo)
    {query, params} = sql.table_exists_query(table)
    query!(adapter_meta, query, params, opts).num_rows != 0
  end

  # Returns a formatted table for a given query `result`.
  #
  # ## Examples
  #
  #     iex> Ecto.Adapters.SQL.format_table(query) |> IO.puts()
  #     +---------------+---------+--------+
  #     | title         | counter | public |
  #     +---------------+---------+--------+
  #     | My Post Title |       1 | NULL   |
  #     +---------------+---------+--------+
  @doc false
  @spec format_table(%{
          :columns => [String.t()] | nil,
          :rows => [term()] | nil,
          optional(atom) => any()
        }) :: String.t()
  def format_table(result)

  def format_table(nil), do: ""
  def format_table(%{columns: nil}), do: ""
  def format_table(%{columns: []}), do: ""

  def format_table(%{columns: columns, rows: nil}),
    do: format_table(%{columns: columns, rows: []})

  def format_table(%{columns: columns, rows: rows}) do
    column_widths =
      [columns | rows]
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)
      |> Enum.map(fn column_with_rows ->
        column_with_rows |> Enum.map(&binary_length/1) |> Enum.max()
      end)

    [
      separator(column_widths),
      "\n",
      cells(columns, column_widths),
      "\n",
      separator(column_widths),
      "\n",
      Enum.map(rows, &(cells(&1, column_widths) ++ ["\n"])),
      separator(column_widths)
    ]
    |> IO.iodata_to_binary()
  end

  # NULL
  defp binary_length(nil), do: 4
  defp binary_length(binary) when is_binary(binary), do: String.length(binary)
  defp binary_length(other), do: other |> inspect() |> String.length()

  defp separator(widths) do
    Enum.map(widths, &[?+, ?-, String.duplicate("-", &1), ?-]) ++ [?+]
  end

  defp cells(items, widths) do
    cell =
      [items, widths]
      |> Enum.zip()
      |> Enum.map(fn {item, width} -> [?|, " ", format_item(item, width), " "] end)

    [cell | [?|]]
  end

  defp format_item(nil, width), do: String.pad_trailing("NULL", width)
  defp format_item(item, width) when is_binary(item), do: String.pad_trailing(item, width)

  defp format_item(item, width) when is_number(item),
    do: item |> inspect() |> String.pad_leading(width)

  defp format_item(item, width), do: item |> inspect() |> String.pad_trailing(width)

  ## Callbacks

  @doc false
  def __before_compile__(_driver, _env) do
    query_doc = @query_doc
    query_bang_doc = @query_bang_doc
    query_many_doc = @query_many_doc
    query_many_bang_doc = @query_many_bang_doc
    to_sql_doc = @to_sql_doc
    explain_doc = @explain_doc
    disconnect_all_doc = @disconnect_all_doc

    quote do
      @doc unquote(query_doc)
      @spec query(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
              {:ok, Ecto.Adapters.SQL.query_result()} | {:error, Exception.t()}
      def query(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query(get_dynamic_repo(), sql, params, opts)
      end

      @doc unquote(query_bang_doc)
      @spec query!(iodata(), Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
              Ecto.Adapters.SQL.query_result()
      def query!(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query!(get_dynamic_repo(), sql, params, opts)
      end

      @doc unquote(query_many_doc)
      @spec query_many(iodata, Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
              {:ok, [Ecto.Adapters.SQL.query_result()]} | {:error, Exception.t()}
      def query_many(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query_many(get_dynamic_repo(), sql, params, opts)
      end

      @doc unquote(query_many_bang_doc)
      @spec query_many!(iodata, Ecto.Adapters.SQL.query_params(), Keyword.t()) ::
              [Ecto.Adapters.SQL.query_result()]
      def query_many!(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query_many!(get_dynamic_repo(), sql, params, opts)
      end

      @doc unquote(to_sql_doc)
      @spec to_sql(:all | :update_all | :delete_all, Ecto.Queryable.t()) ::
              {String.t(), Ecto.Adapters.SQL.query_params()}
      def to_sql(operation, queryable) do
        Ecto.Adapters.SQL.to_sql(operation, get_dynamic_repo(), queryable)
      end

      @doc unquote(explain_doc)
      @spec explain(:all | :update_all | :delete_all, Ecto.Queryable.t(), opts :: Keyword.t()) ::
              String.t() | Exception.t() | list(map)
      def explain(operation, queryable, opts \\ []) do
        Ecto.Adapters.SQL.explain(get_dynamic_repo(), operation, queryable, opts)
      end

      @doc unquote(disconnect_all_doc)
      @spec disconnect_all(non_neg_integer, opts :: Keyword.t()) :: :ok
      def disconnect_all(interval, opts \\ []) do
        Ecto.Adapters.SQL.disconnect_all(get_dynamic_repo(), interval, opts)
      end
    end
  end

  @doc false
  def ensure_all_started(driver, _config, type) do
    Application.ensure_all_started(driver, type)
  end

  @pool_opts [:timeout, :pool, :pool_size] ++
               [:queue_target, :queue_interval, :ownership_timeout, :repo]

  @valid_log_levels ~w(false debug info notice warning error critical alert emergency)a

  @doc false
  def init(connection, driver, config) do
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect(connection)}.

      Please verify you have added #{inspect(driver)} as a dependency:

          {#{inspect(driver)}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean --build ecto
      """
    end

    log = Keyword.get(config, :log, :debug)

    log_stacktrace_mfa =
      Keyword.get(config, :log_stacktrace_mfa, {__MODULE__, :first_non_ecto_stacktrace, [1]})

    if log not in @valid_log_levels do
      raise """
      invalid value for :log option in Repo config

      The accepted values for the :log option are:
      #{Enum.map_join(@valid_log_levels, ", ", &inspect/1)}

      See https://hexdocs.pm/ecto/Ecto.Repo.html for more information.
      """
    end

    stacktrace = Keyword.get(config, :stacktrace)
    telemetry_prefix = Keyword.fetch!(config, :telemetry_prefix)
    telemetry = {config[:repo], log, telemetry_prefix ++ [:query]}

    {name, config} = Keyword.pop(config, :name, config[:repo])
    {pool_count, config} = Keyword.pop(config, :pool_count, 1)
    {pool, config} = pool_config(config)
    child_spec = connection.child_spec(config)

    meta = %{
      telemetry: telemetry,
      sql: connection,
      stacktrace: stacktrace,
      log_stacktrace_mfa: log_stacktrace_mfa,
      opts: Keyword.take(config, @pool_opts)
    }

    if pool_count > 1 do
      if name == nil do
        raise ArgumentError, "the option :pool_count requires a :name"
      end

      if pool == DBConnection.Ownership do
        raise ArgumentError, "the option :pool_count does not work with the SQL sandbox"
      end

      name = Module.concat(name, PartitionSupervisor)
      partition_opts = [name: name, child_spec: child_spec, partitions: pool_count]
      child_spec = Supervisor.child_spec({PartitionSupervisor, partition_opts}, [])
      {:ok, child_spec, Map.put(meta, :partition_supervisor, {name, pool_count})}
    else
      {:ok, child_spec, meta}
    end
  end

  defp pool_config(config) do
    {pool, config} = Keyword.pop(config, :pool, DBConnection.ConnectionPool)

    pool =
      if Code.ensure_loaded?(pool) && function_exported?(pool, :unboxed_run, 2) do
        DBConnection.Ownership
      else
        pool
      end

    {pool, [pool: pool] ++ config}
  end

  @doc false
  def checkout(adapter_meta, opts, callback) do
    checkout_or_transaction(:run, adapter_meta, opts, callback)
  end

  @doc false
  def checked_out?(adapter_meta) do
    %{pid: pool} = adapter_meta
    get_conn(pool) != nil
  end

  ## Query

  @doc false
  def insert_all(
        adapter_meta,
        schema_meta,
        conn,
        header,
        rows,
        on_conflict,
        returning,
        placeholders,
        opts
      ) do
    %{source: source, prefix: prefix} = schema_meta
    {_, conflict_params, _} = on_conflict

    {rows, params} =
      case rows do
        {%Ecto.Query{} = query, params} -> {query, Enum.reverse(params)}
        rows -> unzip_inserts(header, rows)
      end

    sql = conn.insert(prefix, source, header, rows, on_conflict, returning, placeholders)

    opts =
      if is_nil(Keyword.get(opts, :cache_statement)) do
        [{:cache_statement, "ecto_insert_all_#{source}"} | opts]
      else
        opts
      end

    all_params = placeholders ++ Enum.reverse(params, conflict_params)

    %{num_rows: num, rows: rows} = query!(adapter_meta, sql, all_params, [source: source] ++ opts)
    {num, rows}
  end

  defp unzip_inserts(header, rows) do
    Enum.map_reduce(rows, [], fn fields, params ->
      Enum.map_reduce(header, params, fn key, acc ->
        case :lists.keyfind(key, 1, fields) do
          {^key, {%Ecto.Query{} = query, query_params}} ->
            {{query, length(query_params)}, Enum.reverse(query_params, acc)}

          {^key, {:placeholder, placeholder_index}} ->
            {{:placeholder, Integer.to_string(placeholder_index)}, acc}

          {^key, value} ->
            {key, [value | acc]}

          false ->
            {nil, acc}
        end
      end)
    end)
  end

  @doc false
  def execute(prepare, adapter_meta, query_meta, prepared, params, opts) do
    %{num_rows: num, rows: rows} =
      execute!(prepare, adapter_meta, prepared, params, put_source(opts, query_meta))

    {num, rows}
  end

  defp execute!(prepare, adapter_meta, {:cache, update, {id, prepared}}, params, opts) do
    name = prepare_name(prepare, id)

    case sql_call(adapter_meta, :prepare_execute, [name, prepared], params, opts) do
      {:ok, query, result} ->
        maybe_update_cache(prepare, update, {id, query})
        result

      {:error, err} ->
        raise_sql_call_error(err)
    end
  end

  defp execute!(
         :unnamed = prepare,
         adapter_meta,
         {:cached, _update, _reset, {id, cached}},
         params,
         opts
       ) do
    name = prepare_name(prepare, id)
    prepared = String.Chars.to_string(cached)

    case sql_call(adapter_meta, :prepare_execute, [name, prepared], params, opts) do
      {:ok, _query, result} ->
        result

      {:error, err} ->
        raise_sql_call_error(err)
    end
  end

  defp execute!(
         :named = _prepare,
         adapter_meta,
         {:cached, update, reset, {id, cached}},
         params,
         opts
       ) do
    case sql_call(adapter_meta, :execute, [cached], params, opts) do
      {:ok, query, result} ->
        update.({id, query})
        result

      {:ok, result} ->
        result

      {:error, err} ->
        raise_sql_call_error(err)

      {:reset, err} ->
        reset.({id, String.Chars.to_string(cached)})
        raise_sql_call_error(err)
    end
  end

  defp execute!(_prepare, adapter_meta, {:nocache, {_id, prepared}}, params, opts) do
    case sql_call(adapter_meta, :query, [prepared], params, opts) do
      {:ok, res} -> res
      {:error, err} -> raise_sql_call_error(err)
    end
  end

  defp prepare_name(:named, id), do: "ecto_" <> Integer.to_string(id)
  defp prepare_name(:unnamed, _id), do: ""

  defp maybe_update_cache(:named = _prepare, update, value), do: update.(value)
  defp maybe_update_cache(:unnamed = _prepare, _update, _value), do: :noop

  @doc false
  def stream(adapter_meta, query_meta, prepared, params, opts) do
    do_stream(adapter_meta, prepared, params, put_source(opts, query_meta))
  end

  defp do_stream(adapter_meta, {:cache, _, {_, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp do_stream(adapter_meta, {:cached, _, _, {_, cached}}, params, opts) do
    prepare_stream(adapter_meta, String.Chars.to_string(cached), params, opts)
  end

  defp do_stream(adapter_meta, {:nocache, {_id, prepared}}, params, opts) do
    prepare_stream(adapter_meta, prepared, params, opts)
  end

  defp prepare_stream(adapter_meta, prepared, params, opts) do
    adapter_meta
    |> Ecto.Adapters.SQL.Stream.build(prepared, params, opts)
    |> Stream.map(fn %{num_rows: nrows, rows: rows} -> {nrows, rows} end)
  end

  defp raise_sql_call_error(%DBConnection.OwnershipError{} = err) do
    message = err.message <> "\nSee Ecto.Adapters.SQL.Sandbox docs for more information."
    raise %{err | message: message}
  end

  defp raise_sql_call_error(err), do: raise(err)

  @doc false
  def reduce(adapter_meta, statement, params, opts, acc, fun) do
    %{
      pid: pool,
      telemetry: telemetry,
      sql: sql,
      log_stacktrace_mfa: log_stacktrace_mfa,
      opts: default_opts
    } = adapter_meta

    opts = with_log(telemetry, log_stacktrace_mfa, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        sql
        |> apply(:stream, [conn, statement, params, opts])
        |> Enumerable.reduce(acc, fun)

      _ ->
        raise "cannot reduce stream outside of transaction"
    end
  end

  @doc false
  def into(adapter_meta, statement, params, opts) do
    %{
      pid: pool,
      telemetry: telemetry,
      sql: sql,
      opts: default_opts,
      log_stacktrace_mfa: log_stacktrace_mfa
    } = adapter_meta

    opts = with_log(telemetry, log_stacktrace_mfa, params, opts ++ default_opts)

    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn ->
        sql
        |> apply(:stream, [conn, statement, params, opts])
        |> Collectable.into()

      _ ->
        raise "cannot collect into stream outside of transaction"
    end
  end

  @doc false
  def struct(
        adapter_meta,
        conn,
        sql,
        operation,
        source,
        params,
        values,
        on_conflict,
        returning,
        opts
      ) do
    opts =
      if is_nil(Keyword.get(opts, :cache_statement)) do
        [{:cache_statement, "ecto_#{operation}_#{source}_#{length(params)}"} | opts]
      else
        opts
      end

    case query(adapter_meta, sql, values, [source: source] ++ opts) do
      {:ok, %{rows: nil, num_rows: 1}} ->
        {:ok, []}

      {:ok, %{rows: [values], num_rows: 1}} ->
        {:ok, Enum.zip(returning, values)}

      {:ok, %{num_rows: 0}} ->
        if on_conflict == :nothing, do: {:ok, []}, else: {:error, :stale}

      {:ok, %{num_rows: num_rows}} when num_rows > 1 ->
        raise Ecto.MultiplePrimaryKeyError,
          source: source,
          params: params,
          count: num_rows,
          operation: operation

      {:error, err} ->
        case conn.to_constraints(err, source: source) do
          [] -> raise_sql_call_error(err)
          constraints -> {:invalid, constraints}
        end
    end
  end

  ## Transactions

  @doc false
  def transaction(adapter_meta, opts, callback) do
    checkout_or_transaction(:transaction, adapter_meta, opts, callback)
  end

  @doc false
  def in_transaction?(%{pid: pool}) do
    match?(%DBConnection{conn_mode: :transaction}, get_conn(pool))
  end

  @doc false
  def rollback(%{pid: pool}, value) do
    case get_conn(pool) do
      %DBConnection{conn_mode: :transaction} = conn -> DBConnection.rollback(conn, value)
      _ -> raise "cannot call rollback outside of transaction"
    end
  end

  ## Migrations

  @doc false
  def execute_ddl(meta, conn, definition, opts) do
    ddl_logs =
      definition
      |> conn.execute_ddl()
      |> List.wrap()
      |> Enum.map(&query!(meta, &1, [], opts))
      |> Enum.flat_map(&conn.ddl_logs/1)

    {:ok, ddl_logs}
  end

  @doc false
  def raise_migration_pool_size_error do
    raise Ecto.MigrationError, """
    Migrations failed to run because the connection pool size is less than 2.

    Ecto requires a pool size of at least 2 to support concurrent migrators.
    When migrations run, Ecto uses one connection to maintain a lock and
    another to run migrations.

    If you are running migrations with Mix, you can increase the number
    of connections via the pool size option:

        mix ecto.migrate --pool-size 2

    If you are running the Ecto.Migrator programmatically, you can configure
    the pool size via your application config:

        config :my_app, Repo,
          ...,
          pool_size: 2 # at least
    """
  end

  ## Log

  defp with_log(telemetry, log_stacktrace_mfa, params, opts) do
    [log: &log(telemetry, log_stacktrace_mfa, params, &1, opts)] ++ opts
  end

  defp log({repo, log, event_name}, log_stacktrace_mfa, params, entry, opts) do
    %{
      connection_time: query_time,
      decode_time: decode_time,
      pool_time: queue_time,
      idle_time: idle_time,
      result: result,
      query: query
    } = entry

    source = Keyword.get(opts, :source)
    query = String.Chars.to_string(query)
    result = with {:ok, _query, res} <- result, do: {:ok, res}
    stacktrace = Keyword.get(opts, :stacktrace)
    log_params = opts[:cast_params] || params

    acc = if idle_time, do: [idle_time: idle_time], else: []

    measurements =
      log_measurements(
        [query_time: query_time, decode_time: decode_time, queue_time: queue_time],
        0,
        acc
      )

    metadata = %{
      type: :ecto_sql_query,
      repo: repo,
      result: result,
      params: params,
      cast_params: opts[:cast_params],
      query: query,
      source: source,
      stacktrace: stacktrace,
      options: Keyword.get(opts, :telemetry_options, [])
    }

    if event_name = Keyword.get(opts, :telemetry_event, event_name) do
      :telemetry.execute(event_name, measurements, metadata)
    end

    case {opts[:log], log} do
      {false, _level} ->
        :ok

      {opts_level, false} when opts_level in [nil, true] ->
        :ok

      {true, level} ->
        Logger.log(
          level,
          fn ->
            log_iodata(
              measurements,
              repo,
              source,
              query,
              log_params,
              result,
              stacktrace,
              opts[:log_stacktrace_mfa] || log_stacktrace_mfa
            )
          end,
          ansi_color: sql_color(query)
        )

      {opts_level, args_level} ->
        Logger.log(
          opts_level || args_level,
          fn ->
            log_iodata(
              measurements,
              repo,
              source,
              query,
              log_params,
              result,
              stacktrace,
              opts[:log_stacktrace_mfa] || log_stacktrace_mfa
            )
          end,
          ansi_color: sql_color(query)
        )
    end

    :ok
  end

  defp log_measurements([{_, nil} | rest], total, acc),
    do: log_measurements(rest, total, acc)

  defp log_measurements([{key, value} | rest], total, acc),
    do: log_measurements(rest, total + value, [{key, value} | acc])

  defp log_measurements([], total, acc),
    do: Map.new([total_time: total] ++ acc)

  defp log_iodata(measurements, repo, source, query, params, result, stacktrace, stacktrace_mfa) do
    [
      "QUERY",
      ?\s,
      log_ok_error(result),
      log_ok_source(source),
      log_time("db", measurements, :query_time, true),
      log_time("decode", measurements, :decode_time, false),
      log_time("queue", measurements, :queue_time, false),
      log_time("idle", measurements, :idle_time, true),
      ?\n,
      query,
      ?\s,
      inspect(params, charlists: false),
      log_stacktrace(stacktrace, repo, stacktrace_mfa)
    ]
  end

  defp log_ok_error({:ok, _res}), do: "OK"
  defp log_ok_error({:error, _err}), do: "ERROR"

  defp log_ok_source(nil), do: ""
  defp log_ok_source(source), do: " source=#{inspect(source)}"

  defp log_time(label, measurements, key, force) do
    case measurements do
      %{^key => time} ->
        us = System.convert_time_unit(time, :native, :microsecond)
        ms = div(us, 100) / 10

        if force or ms > 0 do
          [?\s, label, ?=, :io_lib_format.fwrite_g(ms), ?m, ?s]
        else
          []
        end

      %{} ->
        []
    end
  end

  defp log_stacktrace([_ | _] = stacktrace, repo, {module, function, args}) do
    entries = apply(module, function, [stacktrace, %{repo: repo} | args])

    Enum.with_index(entries, fn {module, function, arity, info}, idx ->
      [
        ?\n,
        IO.ANSI.light_black(),
        if(idx == 0, do: "↳ ", else: "  "),
        Exception.format_mfa(module, function, arity),
        log_stacktrace_info(info),
        IO.ANSI.reset()
      ]
    end)
  end

  defp log_stacktrace(_, _, _), do: []

  defp log_stacktrace_info([file: file, line: line] ++ _) do
    [", at: ", file, ?:, Integer.to_string(line)]
  end

  defp log_stacktrace_info(_) do
    []
  end

  @repo_modules [Ecto.Repo.Queryable, Ecto.Repo.Schema, Ecto.Repo.Transaction]

  @doc """
  Receives a stacktrace, and return the first N items before Ecto entries

  This function is used by default in the `:log_stacktrace_mfa` config, with
  a size of 1.
  """
  @spec first_non_ecto_stacktrace(
          Exception.stacktrace(),
          %{repo: Ecto.Repo.t()},
          non_neg_integer()
        ) :: Exception.stacktrace()
  def first_non_ecto_stacktrace(stacktrace, %{repo: repo}, size) do
    stacktrace
    |> Enum.reverse()
    |> last_non_ecto_entries(repo, [])
    |> Enum.take(size)
  end

  defp last_non_ecto_entries([{mod, _, _, _} | _], repo, acc)
       when mod == repo or mod in @repo_modules,
       do: acc

  defp last_non_ecto_entries([entry | rest], repo, acc),
    do: last_non_ecto_entries(rest, repo, [entry | acc])

  defp last_non_ecto_entries([], _, acc), do: acc

  ## Connection helpers

  defp checkout_or_transaction(fun, adapter_meta, opts, callback) do
    %{pid: pool, telemetry: telemetry, opts: default_opts, log_stacktrace_mfa: log_stacktrace_mfa} =
      adapter_meta

    opts = with_log(telemetry, log_stacktrace_mfa, [], opts ++ default_opts)

    callback = fn conn ->
      previous_conn = put_conn(pool, conn)

      try do
        callback.()
      after
        reset_conn(pool, previous_conn)
      end
    end

    apply(DBConnection, fun, [get_conn_or_pool(pool, adapter_meta), callback, opts])
  end

  defp get_conn_or_pool(pool, adapter_meta) do
    case :erlang.get(key(pool)) do
      :undefined ->
        case adapter_meta do
          %{partition_supervisor: {name, _}} -> {:via, PartitionSupervisor, {name, self()}}
          _ -> pool
        end

      conn ->
        conn
    end
  end

  defp get_conn(pool) do
    Process.get(key(pool))
  end

  defp put_conn(pool, conn) do
    Process.put(key(pool), conn)
  end

  defp reset_conn(pool, conn) do
    if conn do
      put_conn(pool, conn)
    else
      Process.delete(key(pool))
    end
  end

  defp key(pool), do: {__MODULE__, pool}

  defp sql_color("SELECT" <> _), do: :cyan
  defp sql_color("ROLLBACK" <> _), do: :red
  defp sql_color("LOCK" <> _), do: :white
  defp sql_color("INSERT" <> _), do: :green
  defp sql_color("UPDATE" <> _), do: :yellow
  defp sql_color("DELETE" <> _), do: :red
  defp sql_color("begin" <> _), do: :magenta
  defp sql_color("commit" <> _), do: :magenta
  defp sql_color(_), do: nil
end
