defmodule Ecto.Adapters.SQL.Connection do
  @moduledoc """
  Specifies the behaviour to be implemented by all SQL connections.
  """

  @typedoc "The query name"
  @type name :: String.t()

  @typedoc "The SQL statement"
  @type statement :: String.t()

  @typedoc "The cached query which is a DBConnection Query"
  @type cached :: map

  @type connection :: DBConnection.conn()
  @type params :: [term]

  @doc """
  Receives options and returns `DBConnection` supervisor child
  specification.
  """
  @callback child_spec(options :: Keyword.t()) :: :supervisor.child_spec() | {module, Keyword.t()}

  @doc """
  Prepares and executes the given query with `DBConnection`.
  """
  @callback prepare_execute(connection, name, statement, params, options :: Keyword.t()) ::
              {:ok, cached, term} | {:error, Exception.t()}

  @doc """
  Executes a cached query.
  """
  @callback execute(connection, cached, params, options :: Keyword.t()) ::
              {:ok, cached, term} | {:ok, term} | {:error | :reset, Exception.t()}

  @doc """
  Runs the given statement as a query.
  """
  @callback query(connection, statement, params, options :: Keyword.t()) ::
              {:ok, term} | {:error, Exception.t()}

  @doc """
  Runs the given statement as a multi-result query.
  """
  @callback query_many(connection, statement, params, options :: Keyword.t()) ::
              {:ok, term} | {:error, Exception.t()}

  @doc """
  Returns a stream that prepares and executes the given query with
  `DBConnection`.
  """
  @callback stream(connection, statement, params, options :: Keyword.t()) ::
              Enum.t()

  @doc """
  Receives the exception returned by `c:query/4`.

  The constraints are in the keyword list and must return the
  constraint type, like `:unique`, and the constraint name as
  a string, for example:

      [unique: "posts_title_index"]

  Must return an empty list if the error does not come
  from any constraint.
  """
  @callback to_constraints(exception :: Exception.t(), options :: Keyword.t()) :: Keyword.t()

  ## Queries

  @doc """
  Receives a query and must return a SELECT query.
  """
  @callback all(query :: Ecto.Query.t()) :: iodata

  @doc """
  Receives a query and values to update and must return an UPDATE query.
  """
  @callback update_all(query :: Ecto.Query.t()) :: iodata

  @doc """
  Receives a query and must return a DELETE query.
  """
  @callback delete_all(query :: Ecto.Query.t()) :: iodata

  @doc """
  Returns an INSERT for the given `rows` in `table` returning
  the given `returning`.
  """
  @callback insert(
              prefix :: String.t(),
              table :: String.t(),
              header :: [atom],
              rows :: [[atom | nil]],
              on_conflict :: Ecto.Adapter.Schema.on_conflict(),
              returning :: [atom],
              placeholders :: [term]
            ) :: iodata

  @doc """
  Returns an UPDATE for the given `fields` in `table` filtered by
  `filters` returning the given `returning`.
  """
  @callback update(
              prefix :: String.t(),
              table :: String.t(),
              fields :: [atom],
              filters :: [atom],
              returning :: [atom]
            ) :: iodata

  @doc """
  Returns a DELETE for the `filters` returning the given `returning`.
  """
  @callback delete(
              prefix :: String.t(),
              table :: String.t(),
              filters :: [atom],
              returning :: [atom]
            ) :: iodata

  @doc """
  Executes an EXPLAIN query or similar depending on the adapter to obtains statistics of the given query.

  Receives the `connection`, `query`, `params` for the query,
  and all `opts` including those related to the EXPLAIN statement and shared opts.

  Must execute the explain query and return the result.
  """
  @callback explain_query(
              connection,
              query :: String.t(),
              params :: Keyword.t(),
              opts :: Keyword.t()
            ) ::
              {:ok, term} | {:error, Exception.t()}

  ## DDL

  @doc """
  Receives a DDL command and returns a query that executes it.
  """
  @callback execute_ddl(command :: Ecto.Adapter.Migration.command()) :: String.t() | [iodata]

  @doc """
  Receives a query result and returns a list of logs.
  """
  @callback ddl_logs(result :: term) :: [{Logger.level(), Logger.message(), Logger.metadata()}]

  @doc """
  Returns a queryable to check if the given `table` exists.
  """
  @callback table_exists_query(table :: String.t()) :: {iodata, [term]}
end
