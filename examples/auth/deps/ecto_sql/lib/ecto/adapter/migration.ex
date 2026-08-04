defmodule Ecto.Adapter.Migration do
  @moduledoc """
  Specifies the adapter migrations API.
  """

  alias Ecto.Migration.Constraint
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index
  alias Ecto.Migration.Reference

  @type adapter_meta :: Ecto.Adapter.adapter_meta()

  @type drop_mode :: :restrict | :cascade

  @typedoc "All migration commands"
  @type command ::
          raw ::
          String.t()
          | {:create, Table.t(), [table_subcommand]}
          | {:create_if_not_exists, Table.t(), [table_subcommand]}
          | {:alter, Table.t(), [table_subcommand]}
          | {:drop, Table.t(), drop_mode()}
          | {:drop_if_exists, Table.t(), drop_mode()}
          | {:create, Index.t()}
          | {:create_if_not_exists, Index.t()}
          | {:drop, Index.t(), drop_mode()}
          | {:drop_if_exists, Index.t(), drop_mode()}
          | {:create, Constraint.t()}
          | {:drop, Constraint.t(), drop_mode()}
          | {:drop_if_exists, Constraint.t(), drop_mode()}

  @typedoc "All commands allowed within the block passed to `table/2`"
  @type table_subcommand ::
          {:add, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(), Keyword.t()}
          | {:add_if_not_exists, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:modify, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:remove, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary(),
             Keyword.t()}
          | {:remove, field :: atom}
          | {:remove_if_exists, field :: atom, type :: Ecto.Type.t() | Reference.t() | binary()}
          | {:remove_if_exists, field :: atom}

  @typedoc """
  A struct that represents a table or index in a database schema.

  These database objects can be modified through the use of a Data
  Definition Language, hence the name DDL object.
  """
  @type ddl_object :: Table.t() | Index.t()

  @doc """
  Checks if the adapter supports ddl transaction.
  """
  @callback supports_ddl_transaction? :: boolean

  @doc """
  Executes migration commands.
  """
  @callback execute_ddl(adapter_meta, command, options :: Keyword.t()) ::
              {:ok, [{Logger.level(), Logger.message(), Logger.metadata()}]}

  @doc """
  Locks the migrations table and emits the locked versions for callback execution.

  It returns the result of calling the given function with a list of versions.
  """
  @callback lock_for_migrations(adapter_meta, options :: Keyword.t(), fun) ::
              result
            when fun: (-> result), result: var
end
