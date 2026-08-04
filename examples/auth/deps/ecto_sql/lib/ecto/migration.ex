defmodule Ecto.Migration do
  @moduledoc """
  Migrations are used to modify your database schema over time.

  This module provides many helpers for migrating the database,
  allowing developers to use Elixir to alter their storage in
  a way that is database independent.

  Migrations typically provide two operations: `up` and `down`,
  allowing us to migrate the database forward or roll it back
  in case of errors.

  In order to manage migrations, Ecto creates a table called
  `schema_migrations` in the database, which stores all migrations
  that have already been executed. You can configure the name of
  this table with the `:migration_source` configuration option
  and the name of the repository that manages it with `:migration_repo`.

  Ecto locks the `schema_migrations` table when running
  migrations, guaranteeing two different servers cannot run the same
  migration at the same time.

  ## Creating your first migration

  Migrations are defined inside the "priv/REPO/migrations" where REPO
  is the last part of the repository name in underscore. For example,
  migrations for `MyApp.Repo` would be found in "priv/repo/migrations".
  For `MyApp.CustomRepo`, it would be found in "priv/custom_repo/migrations".

  Each file in the migrations directory has the following structure:

  ```text
  NUMBER_NAME.exs
  ```

  The NUMBER is a unique number that identifies the migration. It is
  usually the timestamp of when the migration was created. The NAME
  must also be unique and it quickly identifies what the migration
  does. For example, if you need to track the "weather" in your system,
  you can start a new file at "priv/repo/migrations/20190417140000_add_weather_table.exs"
  that will have the following contents:

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def up do
          create table("weather") do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end

        def down do
          drop table("weather")
        end
      end

  The `up/0` function is responsible to migrate your database forward.
  the `down/0` function is executed whenever you want to rollback.
  The `down/0` function must always do the opposite of `up/0`.
  Inside those functions, we invoke the API defined in this module,
  you will find conveniences for managing tables, indexes, columns,
  references, as well as running custom SQL commands.

  To run a migration, we generally use Mix tasks. For example, you can
  run the migration above by going to the root of your project and
  typing:

      $ mix ecto.migrate

  You can also roll it back by calling:

      $ mix ecto.rollback --step 1

  Note rollback requires us to say how much we want to rollback.
  On the other hand, `mix ecto.migrate` will always run all pending
  migrations.

  In practice, we don't create migration files by hand either, we
  typically use `mix ecto.gen.migration` to generate the file with
  the proper timestamp and then we just fill in its contents:

      $ mix ecto.gen.migration add_weather_table

  For the rest of this document, we will cover the migration APIs
  provided by Ecto. For a in-depth discussion of migrations and how
  to use them safely within your application and data, see the
  [Safe Ecto Migrations guide](https://fly.io/phoenix-files/safe-ecto-migrations/).

  ## Mix tasks

  As seen above, Ecto provides many Mix tasks to help developers work
  with migrations. We summarize them below:

    * `mix ecto.gen.migration` - generates a
      migration that the user can fill in with particular commands
    * `mix ecto.migrate` - migrates a repository
    * `mix ecto.migrations` - shows all migrations and their status
    * `mix ecto.rollback` - rolls back a particular migration

  Run `mix help COMMAND` for more information on a particular command.
  For a lower level API for running migrations, see `Ecto.Migrator`.

  ## Change

  Having to write both `up/0` and `down/0` functions for every
  migration is tedious and error prone. For this reason, Ecto allows
  you to define a `change/0` callback with all of the code you want
  to execute when migrating and Ecto will automatically figure out
  the `down/0` for you. For example, the migration above can be
  written as:

      defmodule MyRepo.Migrations.AddWeatherTable do
        use Ecto.Migration

        def change do
          create table("weather") do
            add :city,    :string, size: 40
            add :temp_lo, :integer
            add :temp_hi, :integer
            add :prcp,    :float

            timestamps()
          end
        end
      end

  However, note that not all commands are reversible. Trying to rollback
  a non-reversible command will raise an `Ecto.MigrationError`.

  A notable command in this regard is `execute/2`, which is reversible in
  `change/0` by accepting a pair of plain SQL strings. The first is run on
  forward migrations (`up/0`) and the second when rolling back (`down/0`).

  If `up/0` and `down/0` are implemented in a migration, they take precedence,
  and `change/0` isn't invoked.

  ## Field Types

  The [Ecto primitive types](https://hexdocs.pm/ecto/Ecto.Schema.html#module-primitive-types) are mapped to the appropriate database
  type by the various database adapters. For example, `:string` is
  converted to `:varchar`, `:binary` to `:bytea` or `:blob`, and so on.

  In particular, note that:

    * the `:string` type in migrations by default has a limit of 255 characters.
      If you need more or less characters, pass the `:size` option, such
      as `add :field, :string, size: 10`. If you don't want to impose a limit,
      most databases support a `:text` type or similar

    * the `:binary` type in migrations by default has no size limit. If you want
      to impose a limit, pass the `:size` option accordingly. In MySQL, passing
      the size option changes the underlying field from "blob" to "varbinary"

  Any other type will be given as is to the database. For example, you
  can use `:text`, `:char`, or `:varchar` as types. Types that have spaces
  in their names can be wrapped in double quotes, such as `:"int unsigned"`,
  `:"time without time zone"`, etc.

  ## Executing and flushing

  Most functions in this module, when executed inside of migrations, are not
  executed immediately. Instead they are performed after the relevant `up`,
  `change`, or `down` callback terminates. Any other functions, such as
  functions provided by `Ecto.Repo`, will be executed immediately unless they
  are called from within an anonymous function passed to `execute/1`.

  In some situations you may want to guarantee that all of the previous steps
  have been executed before continuing. This is useful when you need to apply a
  set of changes to the table before continuing with the migration. This can be
  done with `flush/0`:

      def up do
        ...
        flush()
        ...
      end

  However `flush/0` will raise if it would be called from `change` function when doing a rollback.
  To avoid that we recommend to use `execute/2` with anonymous functions instead.
  For more information and example usage please take a look at `execute/2` function.

  ## Formatter configuration

  To enable Ecto's custom `mix format` rules in your migrations, you can create a new formatter
  config file in your project called `priv/[your_repo]/migrations/.formatter.exs` with the
  following content:

  ```elixir
  [
    import_deps: [:ecto_sql],
    inputs: ["*.exs"]
  ]
  ```

  You will also need to add a line or two to your project's main formatter config so that the
  formatter knows where to find the new config file. Update (or create) your project's main
  `.formatter.exs` file:

  ```elixir
  [
    # Add this line to enable Ecto formatter rules
    import_deps: [:ecto],

    # Add this line to enable Ecto's formatter rules in your migrations directory
    subdirectories: ["priv/*/migrations"],

    # Default Elixir project rules
    inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
  ]
  ```

  Now, when you run `mix format`, the formatter should apply Ecto's custom rules when formatting
  your migrations (e.g. no brackets are automatically added when creating columns with `add/3`). 

  ## Repo configuration

  ### Migrator configuration

  These options configure where Ecto stores and how Ecto runs your migrations:

    * `:migration_source` - Version numbers of migrations will be saved in a
      table named `schema_migrations` by default. You can configure the name of
      the table via:

          config :app, App.Repo, migration_source: "my_migrations"

    * `:migration_lock` - By default, Ecto will lock the migration source to throttle
      multiple nodes to run migrations one at a time. You can disable the `migration_lock`
      by setting it to `false`. You may also select a different locking strategy if
      supported by the adapter. See the adapter docs for more information.

          config :app, App.Repo, migration_lock: false

          # Or use a different locking strategy. For example, Postgres can use advisory
          # locks but be aware that your database configuration might not make this a good
          # fit. See the Ecto.Adapters.Postgres for more information:
          config :app, App.Repo, migration_lock: :pg_advisory_lock

    * `:migration_repo` - The migration repository is where the table managing the
      migrations will be stored (`migration_source` defines the table name). It defaults
      to the given repository itself but you can configure it via:

          config :app, App.Repo, migration_repo: App.MigrationRepo

    * `:migration_cast_version_column` - Ecto uses a `version` column of type
      `bigint` for the underlying migrations table (usually `schema_migrations`). By
      default, Ecto doesn't cast this to a different type when reading or writing to
      the database when running migrations. However, some web frameworks store this
      column as a string. For compatibility reasons, you can set this option to `true`,
      which makes Ecto perform a `CAST(version AS int)`. This used to be the default
      behavior up to Ecto 3.10, so if you are upgrading to 3.11+ and want to keep the
      old behavior, set this option to `true`.

    * `:priv` - the priv directory for the repo with the location of important assets,
      such as migrations. For a repository named `MyApp.FooRepo`, `:priv` defaults to
      "priv/foo_repo" and migrations should be placed at "priv/foo_repo/migrations"

    * `:start_apps_before_migration` - A list of applications to be started before
      running migrations. Used by `Ecto.Migrator.with_repo/3` and the migration tasks:

          config :app, App.Repo, start_apps_before_migration: [:ssl, :some_custom_logger]

  ### Migrations configuration

  These options configure the default values used by migrations. **It is generally
  discouraged to change any of those configurations after your database is deployed
  to production, as changing these options will retroactively change how all
  migrations work**.

    * `:migration_primary_key` - By default, Ecto uses the `:id` column with type
      `:bigserial`, but you can configure it via:

          config :app, App.Repo, migration_primary_key: [name: :uuid, type: :binary_id]

          config :app, App.Repo, migration_primary_key: false

      For Postgres version >= 10 `:identity` key may be used.
      By default, all :identity column will be bigints. You may provide optional
      parameters for `:start_value` and `:increment` to customize the created
      sequence. Config example:

          config :app, App.Repo, migration_primary_key: [type: :identity]

    * `:migration_foreign_key` - By default, Ecto uses the `primary_key` type
      for foreign keys when `references/2` is used, but you can configure it via:

          config :app, App.Repo, migration_foreign_key: [column: :uuid, type: :binary_id]

    * `:migration_timestamps` - By default, Ecto uses the `:naive_datetime` as the type,
      `:inserted_at` as the name of the column for storing insertion times, `:updated_at` as
      the name of the column for storing last-updated-at times, but you can configure it
      via:

          config :app, App.Repo, migration_timestamps: [
            type: :utc_datetime,
            inserted_at: :created_at,
            updated_at: :changed_at
          ]

    * `:migration_default_prefix` - Ecto defaults to `nil` for the database prefix for
      migrations, but you can configure it via:

          config :app, App.Repo, migration_default_prefix: "my_prefix"

  ## Collations

  Collations can be set on a column with the option `:collation`. This can be
  useful when relying on ASCII sorting of characters when using a fractional index
  for example. All supported collations and types that support setting a collocation
  are not known by `ecto_sql` and specifying an incorrect collation or a collation on
  an unsupported type might cause a migration to fail. Be sure to match the collation
  on any column that references another column.

      def change do
        create table(:collate_reference) do
          add :name, :string, collation: "POSIX"
        end

        create table(:collate) do
          add :string, :string, collation: "POSIX"
          add :name_ref, references(:collate_reference, type: :string, column: :name), collation: "POSIX"
        end
      end

  ## Comments

  Migrations where you create or alter a table support specifying table
  and column comments. The same can be done when creating constraints
  and indexes. Not all databases support this feature.

      def up do
        create index("posts", [:name], comment: "Index Comment")
        create constraint("products", "price_must_be_positive", check: "price > 0", comment: "Constraint Comment")
        create table("weather", prefix: "north_america", comment: "Table Comment") do
          add :city, :string, size: 40, comment: "Column Comment"
          timestamps()
        end
      end

  ## Prefixes

  Migrations support specifying a table prefix or index prefix which will
  target either a schema (if using PostgreSQL) or a different database (if using
  MySQL). If no prefix is provided, the default schema or database is used.

  Any reference declared in the table migration refers by default to the table
  with the same declared prefix. The prefix is specified in the table options:

      def up do
        create table("weather", prefix: "north_america") do
          add :city,    :string, size: 40
          add :temp_lo, :integer
          add :temp_hi, :integer
          add :prcp,    :float
          add :group_id, references(:groups)

          timestamps()
        end

        create index("weather", [:city], prefix: "north_america")
      end

  Note: if using MySQL with a prefixed table, you must use the same prefix
  for the references since cross-database references are not supported.

  When using a prefixed table with either MySQL or PostgreSQL, you must use the
  same prefix for the index field to ensure that you index the prefix-qualified
  table.

  ## Transaction Callbacks

  If possible, each migration runs inside a transaction. This is true for Postgres,
  but not true for MySQL, as the latter does not support DDL transactions.

  In some rare cases, you may need to execute some common behavior after beginning
  a migration transaction, or before committing that transaction. For instance, one
  might desire to set a `lock_timeout` for each lock in the migration transaction.

  You can do so by defining `c:after_begin/0` and `c:before_commit/0` callbacks to
  your migration.

  However, if you need do so for every migration module, implement this callback
  for every migration can be quite repetitive. Luckily, you can handle this by
  providing your migration module:

      defmodule MyApp.Migration do
        defmacro __using__(_) do
          quote do
            use Ecto.Migration

            def after_begin() do
              repo().query! "SET lock_timeout TO '5s'"
            end
          end
        end
      end

  Then in your migrations you can `use MyApp.Migration` to share this behavior
  among all your migrations.

  ## Additional resources

    * The [Safe Ecto Migrations guide](https://fly.io/phoenix-files/safe-ecto-migrations/)

  """

  @doc """
  Migration code to run immediately after the transaction is opened.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback after_begin() :: term

  @doc """
  Migration code to run immediately before the transaction is closed.

  Keep in mind that it is treated like any normal migration code, and should
  consider both the up *and* down cases of the migration.
  """
  @callback before_commit() :: term
  @optional_callbacks after_begin: 0, before_commit: 0

  defmodule Index do
    @moduledoc """
    Used internally by adapters.

    To define an index in a migration, see `Ecto.Migration.index/3`.
    """
    defstruct table: nil,
              prefix: nil,
              name: nil,
              columns: [],
              unique: false,
              concurrently: false,
              using: nil,
              include: [],
              only: false,
              nulls_distinct: nil,
              where: nil,
              comment: nil,
              options: nil

    @type column :: atom | String.t() | {index_dir(), atom | String.t()}

    @type index_dir ::
            :asc
            | :asc_nulls_first
            | :asc_nulls_last
            | :desc
            | :desc_nulls_first
            | :desc_nulls_last

    @type t :: %__MODULE__{
            table: String.t(),
            prefix: String.t() | nil,
            name: String.t() | atom,
            columns: [column()],
            unique: boolean,
            concurrently: boolean,
            using: atom | String.t(),
            only: boolean,
            include: [atom | String.t()],
            nulls_distinct: boolean | nil,
            where: atom | String.t(),
            comment: String.t() | nil,
            options: String.t()
          }
  end

  defmodule Table do
    @moduledoc """
    Used internally by adapters.

    To define a table in a migration, see `Ecto.Migration.table/2`.
    """
    defstruct name: nil, prefix: nil, comment: nil, primary_key: true, engine: nil, options: nil

    @type t :: %__MODULE__{
            name: String.t(),
            prefix: String.t() | nil,
            comment: String.t() | nil,
            primary_key: boolean | keyword(),
            engine: atom,
            options: String.t()
          }
  end

  defmodule Reference do
    @moduledoc """
    Used internally by adapters.

    To define a reference in a migration, see `Ecto.Migration.references/2`.
    """
    defstruct name: nil,
              prefix: nil,
              table: nil,
              column: :id,
              type: :bigserial,
              on_delete: :nothing,
              on_update: :nothing,
              validate: true,
              with: [],
              match: nil,
              options: []

    @typedoc """
    The reference struct.

    The `:prefix` field is deprecated and should instead be stored in the `:options` field.
    """
    @type t :: %__MODULE__{
            table: String.t(),
            prefix: String.t() | nil,
            column: atom,
            type: atom,
            on_delete: atom,
            on_update: atom,
            validate: boolean,
            with: list,
            match: atom | nil,
            options: [{:prefix, String.t() | nil}]
          }
  end

  defmodule Constraint do
    @moduledoc """
    Used internally by adapters.

    To define a constraint in a migration, see `Ecto.Migration.constraint/3`.
    """
    defstruct name: nil,
              table: nil,
              check: nil,
              exclude: nil,
              prefix: nil,
              comment: nil,
              validate: true

    @type t :: %__MODULE__{
            name: atom,
            table: String.t(),
            prefix: String.t() | nil,
            check: String.t() | nil,
            exclude: String.t() | nil,
            comment: String.t() | nil,
            validate: boolean
          }
  end

  defmodule Command do
    @moduledoc """
    Used internally by adapters.

    This represents the up and down legs of a reversible raw command
    that is usually defined with `Ecto.Migration.execute/1`.

    To define a reversible command in a migration, see `Ecto.Migration.execute/2`.
    """
    defstruct up: nil, down: nil
    @type t :: %__MODULE__{up: String.t(), down: String.t()}
  end

  alias Ecto.Migration.Runner

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      import Ecto.Migration
      @disable_ddl_transaction false
      @disable_migration_lock false
      @before_compile Ecto.Migration
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      def __migration__ do
        [
          disable_ddl_transaction: @disable_ddl_transaction,
          disable_migration_lock: @disable_migration_lock
        ]
      end
    end
  end

  @doc """
  Creates a table.

  By default, the table will also include an `:id` primary key field that
  has a type of `:bigserial`. Check the `table/2` docs for more information.

  ## Examples

      create table(:posts) do
        add :title, :string, default: "Untitled"
        add :body,  :text

        timestamps()
      end

  """
  defmacro create(object, do: block) do
    expand_create(object, :create, block)
  end

  @doc """
  Creates a table if it does not exist.

  Works just like `create/2` but does not raise an error when the table
  already exists.
  """
  defmacro create_if_not_exists(object, do: block) do
    expand_create(object, :create_if_not_exists, block)
  end

  defp expand_create(object, command, block) do
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({unquote(command), Ecto.Migration.__prefix__(table)})

      if primary_key = Ecto.Migration.__primary_key__(table) do
        {name, type, opts} = primary_key
        add(name, type, opts)
      end

      unquote(block)
      Runner.end_command()
      table
    end
  end

  @doc """
  Alters a table.

  ## Examples

      alter table("posts") do
        add :summary, :text
        modify :title, :text
        remove :views
      end

  """
  defmacro alter(object, do: block) do
    quote do
      table = %Table{} = unquote(object)
      Runner.start_command({:alter, Ecto.Migration.__prefix__(table)})
      unquote(block)
      Runner.end_command()
    end
  end

  @doc """
  Creates one of the following:

    * an index
    * a table with only the :id primary key
    * a constraint

  When reversing (in a `change/0` running backwards), indexes are only dropped
  if they exist, and no errors are raised. To enforce dropping an index, use
  `drop/1`.

  ## Examples

      create index("posts", [:name])
      create table("version")
      create constraint("products", "price_must_be_positive", check: "price > 0")

  """
  def create(%Index{} = index) do
    Runner.execute({:create, __prefix__(index)})
    index
  end

  def create(%Constraint{} = constraint) do
    Runner.execute({:create, __prefix__(constraint)})
    constraint
  end

  def create(%Table{} = table) do
    do_create(table, :create)
    table
  end

  @doc """
  Creates an index or a table with only `:id` field if one does not yet exist.

  ## Examples

      create_if_not_exists index("posts", [:name])

      create_if_not_exists table("version")

  """
  def create_if_not_exists(%Index{} = index) do
    Runner.execute({:create_if_not_exists, __prefix__(index)})
  end

  def create_if_not_exists(%Table{} = table) do
    do_create(table, :create_if_not_exists)
  end

  defp do_create(table, command) do
    columns =
      if primary_key = Ecto.Migration.__primary_key__(table) do
        {name, type, opts} = primary_key
        [{:add, name, type, opts}]
      else
        []
      end

    Runner.execute({command, __prefix__(table), columns})
  end

  @doc """
  Drops one of the following:

    * an index
    * a table
    * a constraint

  ## Examples

      drop index("posts", [:name])
      drop table("posts")
      drop constraint("products", "price_must_be_positive")
      drop index("posts", [:name]), mode: :cascade
      drop table("posts"), mode: :cascade

  ## Options

    * `:mode` - when set to `:cascade`, automatically drop objects that depend
      on the index, and in turn all objects that depend on those objects
      on the table. Default is `:restrict`

  """
  def drop(%{} = index_or_table_or_constraint, opts \\ []) when is_list(opts) do
    Runner.execute(
      {:drop, __prefix__(index_or_table_or_constraint), Keyword.get(opts, :mode, :restrict)}
    )

    index_or_table_or_constraint
  end

  @doc """
  Drops one of the following if it exists:

    * an index
    * a table
    * a constraint

  Does not raise an error if the specified table or index does not exist.

  ## Examples

      drop_if_exists index("posts", [:name])
      drop_if_exists table("posts")
      drop_if_exists constraint("products", "price_must_be_positive")
      drop_if_exists index("posts", [:name]), mode: :cascade
      drop_if_exists table("posts"), mode: :cascade

  ## Options

    * `:mode` - when set to `:cascade`, automatically drop objects that depend
      on the index, and in turn all objects that depend on those objects
      on the table. Default is `:restrict`

  """
  def drop_if_exists(%{} = index_or_table_or_constraint, opts \\ []) when is_list(opts) do
    mode = Keyword.get(opts, :mode, :restrict)
    Runner.execute({:drop_if_exists, __prefix__(index_or_table_or_constraint), mode})
    index_or_table_or_constraint
  end

  @doc """
  Returns a table struct that can be given to `create/2`, `alter/2`, `drop/1`,
  etc.

  ## Examples

      create table("products") do
        add :name, :string
        add :price, :decimal
      end

      drop table("products")

      create table("products", primary_key: false) do
        add :name, :string
        add :price, :decimal
      end

      create table("daily_prices", primary_key: false, options: "PARTITION BY RANGE (date)") do
        add :name, :string, primary_key: true
        add :date, :date, primary_key: true
        add :price, :decimal
      end

      create table("users", primary_key: false) do
        add :id, :identity, primary_key: true, start_value: 100, increment: 20
      end

  ## Options

    * `:primary_key` - when `false`, a primary key field is not generated on table
      creation. Alternatively, a keyword list in the same style of the
      `:migration_primary_key` repository configuration can be supplied
      to control the generation of the primary key field. The keyword list
      must include `:name` and `:type`. See `add/3` for further options.
    * `:engine` - customizes the table storage for supported databases. For MySQL,
      the default is InnoDB.
    * `:prefix` - the prefix for the table. This prefix will automatically be used
      for all constraints and references defined for this table unless explicitly
      overridden in said constraints/references.
    * `:comment` - adds a comment to the table.
    * `:options` - provide custom options that will be appended after the generated
      statement. For example, "WITH", "INHERITS", or "ON COMMIT" clauses. "PARTITION BY"
      can be provided for databases that support table partitioning.

  """
  def table(name, opts \\ [])

  def table(name, opts) when is_atom(name) do
    table(Atom.to_string(name), opts)
  end

  def table(name, opts) when is_binary(name) and is_list(opts) do
    struct!(%Table{name: name}, opts)
  end

  @doc ~S"""
  Returns an index struct that can be given to `create/1`, `drop/1`, etc.

  Expects the table name as the first argument and the index field(s) as
  the second. The fields can be atoms, representing columns, or strings,
  representing expressions that are sent as-is to the database.

  ## Options

    * `:name` - the name of the index. Can be provided as a string or an atom.
    Defaults to "#{table}_#{column}_index".
    * `:prefix` - specify an optional prefix for the index.
    * `:unique` - indicates whether the index should be unique. Defaults to `false`.
    * `:comment` - adds a comment to the index.
    * `:using` - configures the index type.

  Some options are supported only by some databases:

    * `:concurrently` - indicates whether the index should be created/dropped
      concurrently in MSSQL and PostgreSQL.
    * `:include` - specify fields for a covering index,
      [supported by PostgreSQL only](https://www.postgresql.org/docs/current/indexes-index-only-scans.html).
    * `:nulls_distinct` - specify whether null values should be considered
      distinct for a unique index. Defaults to `nil`, which will not add the
      parameter to the generated SQL and thus use the database default.
      This option is currently only supported by PostgreSQL 15+.
      For MySQL, it is always false. For MSSQL, it is always true.
      See the dedicated section on this option for more information.
    * `:only` - indicates to not recurse creating indexes on partitions.
      [supported by PostgreSQL only](https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITIONING-DECLARATIVE-MAINTENANCE).
    * `:options` - configures index options (WITH clause) for both PostgreSQL
      and MSSQL
    * `:where` - specify conditions for a partial index (PostgreSQL) /
      filtered index (MSSQL).

  ## Adding/dropping indexes concurrently

  PostgreSQL supports adding/dropping indexes concurrently (see the
  [docs](http://www.postgresql.org/docs/current/static/sql-createindex.html)).
  However, this feature does not work well with the transactions used by
  Ecto to guarantee integrity during migrations.

  You can address this with two changes:

    1. Change your repository to use PG advisory locks as the migration lock.
       Note this may not be supported by Postgres-like databases and proxies.

    2. Disable DDL transactions. Doing this removes the guarantee that all of
      the changes in the migration will happen at once, so you will want to
      keep it short.

  If the database adapter supports several migration lock strategies, such as
  Postgrex, then review those strategies and consider using a strategy that
  utilizes advisory locks to facilitate running migrations one at a time even
  across multiple nodes. For example:

  ### Config file (PostgreSQL)

      config MyApp.Repo, migration_lock: :pg_advisory_lock

  ### Migration file

      defmodule MyRepo.Migrations.CreateIndexes do
        use Ecto.Migration
        @disable_ddl_transaction true

        def change do
          create index("posts", [:slug], concurrently: true)
        end
      end

  Alternately, you can add `@disable_migration_lock true` to your migration file.
  This would mean that different nodes in a multi-node setup could run the same
  migration at once. It is recommended to isolate your migrations to a single node
  when using concurrent index creation without an advisory lock.

  ## Index types

  When creating an index, the index type can be specified with the `:using`
  option. The `:using` option can be an atom or a string, and its value is
  passed to the generated `USING` clause as-is.

  For example, PostgreSQL supports several index types like B-tree (the
  default), Hash, GIN, and GiST. More information on index types can be found
  in the [PostgreSQL docs](http://www.postgresql.org/docs/current/indexes-types.html).

  ## Partial indexes

  Databases like PostgreSQL and MSSQL support partial indexes.

  A partial index is an index built over a subset of a table. The subset
  is defined by a conditional expression using the `:where` option.
  The `:where` option can be an atom or a string; its value is passed
  to the generated `WHERE` clause as-is.

  More information on partial indexes can be found in the [PostgreSQL
  docs](http://www.postgresql.org/docs/current/indexes-partial.html).

  ## The `:nulls_distinct` option

  A unique index does not prevent multiple null values by default in most databases.

  For example, imagine we have a "products" table and need to guarantee that
  sku's are unique within their category, but the category is optional.
  Creating a regular unique index over the sku and category_id fields with:

      create index("products", [:sku, :category_id], unique: true)

  will allow products with the same sku to be inserted if their category_id is `nil`.
  The `:nulls_distinct` option can be used to change this behavior by considering
  null values as equal, i.e. not distinct:

      create index("products", [:sku, :category_id], unique: true, nulls_distinct: false)

  This option is currently only supported by PostgreSQL 15+.
  As a workaround for older PostgreSQL versions and other databases, an
  additional partial unique index for the sku can be created:

      create index("products", [:sku, :category_id], unique: true)
      create index("products", [:sku], unique: true, where: "category_id IS NULL")

  ## Sorting direction

  You can specify the sorting direction of the index by using a keyword list:

      create index("products", [desc: sku])

  The following keywords are supported:

    * `:asc`
    * `:asc_nulls_last`
    * `:asc_nulls_first`
    * `:desc`
    * `:desc_nulls_last`
    * `:desc_nulls_first`

  The `*_nulls_first` and `*_nulls_last` variants are not supported by all
  databases.

  ## Examples

      # With no name provided, the name of the below index defaults to
      # products_category_id_sku_index
      create index("products", [:category_id, :sku], unique: true)

      # The name can also be set explicitly
      create index("products", [:category_id, :sku], name: :my_special_name)

      # Indexes can be added concurrently
      create index("products", [:category_id, :sku], concurrently: true)

      # The index type can be specified
      create index("products", [:name], using: :hash)

      # Partial indexes are created by specifying a :where option
      create index("products", [:user_id], where: "price = 0", name: :free_products_index)

      # Covering indexes are created by specifying a :include option
      create index("products", [:user_id], include: [:category_id])

  Indexes also support custom expressions. Some databases may require the
  index expression to be written between parentheses:

      # Create an index on a custom expression
      create index("products", ["(lower(name))"], name: :products_lower_name_index)

      # Create a tsvector GIN index on PostgreSQL
      create index("products", ["(to_tsvector('english', name))"],
                   name: :products_name_vector, using: "GIN")

  If the expression is a column name, it will not be quoted. This may cause issues
  when the column is named after a reserved word. Consider using an atom instead.
  For example, the name `offset` is reserved in many databases so the following
  could produce an error: `create index("products", ["offset"])`.
  """
  def index(table, columns, opts \\ [])

  def index(table, columns, opts) when is_atom(table) do
    index(Atom.to_string(table), columns, opts)
  end

  def index(table, column, opts) when is_binary(table) and is_atom(column) do
    index(table, [column], opts)
  end

  def index(table, columns, opts) when is_binary(table) and is_list(columns) and is_list(opts) do
    validate_index_opts!(opts)
    index = struct!(%Index{table: table, columns: columns}, opts)
    %{index | name: index.name || default_index_name(index)}
  end

  @doc """
  Shortcut for creating a unique index.

  See `index/3` for more information.
  """
  def unique_index(table, columns, opts \\ [])

  def unique_index(table, columns, opts) when is_list(opts) do
    index(table, columns, [unique: true] ++ opts)
  end

  defp default_index_name(index) do
    [index.table, index.columns, "index"]
    |> List.flatten()
    |> Enum.map_join("_", &column_name/1)
    |> String.to_atom()
  end

  defp column_name({_dir, column}), do: column_name(column)

  defp column_name(column) do
    column
    |> to_string()
    |> String.replace(~r"[^\w]", "_")
    |> String.replace_trailing("_", "")
  end

  @doc """
  Executes arbitrary SQL, anonymous function or a keyword command.

  The argument is typically a string, containing the SQL command to be executed.
  Keyword commands exist for non-SQL adapters and are not used in most
  situations.

  You may instead run arbitrary code as part of your migration by supplying an
  anonymous function. This defers execution of the anonymous function until
  the migration callback has terminated (see [Executing and
  flushing](#module-executing-and-flushing)). This is most often used in
  combination with `repo/0` by library authors who want to create high-level
  migration helpers.

  Reversible commands can be defined by calling `execute/2`.

  ## Examples

      execute "CREATE EXTENSION postgres_fdw"

      execute create: "posts", capped: true, size: 1024

      execute(fn -> repo().query!("SELECT $1::integer + $2", [40, 2], [log: :info]) end)

      execute(fn -> repo().update_all("posts", set: [published: true]) end)
  """
  def execute(command) when is_binary(command) or is_function(command, 0) or is_list(command) do
    Runner.execute(command)
  end

  @doc """
  Executes reversible SQL commands.

  This is useful for database-specific functionality that does not
  warrant special support in Ecto, for example, creating and dropping
  a PostgreSQL extension. The `execute/2` form avoids having to define
  separate `up/0` and `down/0` blocks that each contain an `execute/1`
  expression.

  The allowed parameters are explained in `execute/1`.

  ## Examples

      defmodule MyApp.MyMigration do
        use Ecto.Migration

        def change do
          execute "CREATE EXTENSION postgres_fdw", "DROP EXTENSION postgres_fdw"
          execute(&execute_up/0, &execute_down/0)
        end

        defp execute_up, do: repo().query!("select 'Up query …';", [], [log: :info])
        defp execute_down, do: repo().query!("select 'Down query …';", [], [log: :info])
      end
  """
  def execute(up, down)
      when (is_binary(up) or is_function(up, 0) or is_list(up)) and
             (is_binary(down) or is_function(down, 0) or is_list(down)) do
    Runner.execute(%Command{up: up, down: down})
  end

  @doc """
  Executes a SQL command from a file.

  The argument must be a path to a file containing a SQL command.

  Reversible commands can be defined by calling `execute_file/2`.
  """
  def execute_file(path) when is_binary(path) do
    command = File.read!(path)
    Runner.execute(command)
  end

  @doc """
  Executes reversible SQL commands from files.

  Each argument must be a path to a file containing a SQL command.

  See `execute/2` for more information on executing SQL commands.
  """
  def execute_file(up_path, down_path) when is_binary(up_path) and is_binary(down_path) do
    up = File.read!(up_path)
    down = File.read!(down_path)
    Runner.execute(%Command{up: up, down: down})
  end

  @doc """
  Gets the migrator direction.
  """
  @spec direction :: :up | :down
  def direction do
    Runner.migrator_direction()
  end

  @doc """
  Gets the migrator repo.
  """
  @spec repo :: Ecto.Repo.t()
  def repo do
    Runner.repo()
  end

  @doc """
  Gets the migrator prefix.
  """
  def prefix do
    Runner.prefix()
  end

  @doc """
  Adds a column when creating or altering a table.

  This function also accepts Ecto primitive types as column types
  that are normalized by the database adapter. For example,
  `:string` is converted to `:varchar`, `:binary` to `:bits` or `:blob`,
  and so on.

  However, the column type is not always the same as the type used in your
  schema. For example, a schema that has a `:string` field can be supported by
  columns of type `:char`, `:varchar`, `:text`, and others. For this reason,
  this function also accepts `:text` and other type annotations that are native
  to the database. These are passed to the database as-is.

  To sum up, the column type may be either an Ecto primitive type,
  which is normalized in cases where the database does not understand it,
  such as `:string` or `:binary`, or a database type which is passed as-is.
  Custom Ecto types like `Ecto.UUID` are not supported because
  they are application-level concerns and may not always map to the database.

  Note: It may be necessary to quote case-sensitive, user-defined type names.
  For example, PostgreSQL normalizes all identifiers to lower case unless
  they are wrapped in double quotes. To ensure a case-sensitive type name
  is sent properly, it must be defined `:'"LikeThis"'` or `:"\"LikeThis\""`.
  This is not necessary for column names because Ecto quotes them automatically.
  Type names are not automatically quoted because they may be expressions such
  as `varchar(255)`.

  ## Examples

      create table("posts") do
        add :title, :string, default: "Untitled"
      end

      alter table("posts") do
        add :summary, :text               # Database type
        add :object,  :map                # Elixir type which is handled by the database
        add :custom, :'"UserDefinedType"' # A case-sensitive, user-defined type name
        add :identity, :integer, generated: "BY DEFAULT AS IDENTITY" # Postgres generated identity column
        add :generated_psql, :string, generated: "ALWAYS AS (id::text) STORED" # Postgres calculated column
        add :generated_other, :string, generated: "CAST(id AS char)" # MySQL and TDS calculated column
      end

  ## Options

    * `:primary_key` - when `true`, marks this field as the primary key.
      If multiple fields are marked, a composite primary key will be created.
    * `:default` - the column's default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.
    * `:null` - determines whether the column accepts null values. When not specified,
      the database will use its default behaviour (which is to treat the column as nullable
      in most databases).
    * `:size` - the size of the type (for example, the number of characters).
      The default is no size, except for `:string`, which defaults to `255`.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
    * `:comment` - adds a comment to the added column.
    * `:collation` - the collation of the text type.
    * `:after` - positions field after the specified one. Only supported on MySQL,
      it is ignored by other databases.
    * `:generated` - a string representing the expression for a generated column. See
      above for a comprehensive set of examples for each of the built-in adapters. If
      specified alongside `:start_value`/`:increment`, those options will be ignored.
    * `:start_value` - option for `:identity` key, represents initial value in sequence
      generation. Default is defined by the database.
    * `:increment` - option for `:identity` key, represents increment value for
      sequence generation. Default is defined by the database.
    * `:fields` - option for `:duration` type. Restricts the set of stored interval fields
      in the database.

  """
  def add(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand({:add, column, type, opts})
  end

  @doc """
  Adds a column if it does not exist yet when altering a table.

  If the `type` value is a `%Reference{}`, it is used to add a constraint.

  `type` and `opts` are exactly the same as in `add/3`.

  This command is not reversible as Ecto does not know about column existence before the creation attempt.

  ## Examples

      alter table("posts") do
        add_if_not_exists :title, :string, default: ""
      end

  """
  def add_if_not_exists(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand({:add_if_not_exists, column, type, opts})
  end

  @doc """
  Renames a table or index.

  ## Examples

      # rename a table
      rename table("posts"), to: table("new_posts")

      # rename an index
      rename(index(:people, [:name], name: "persons_name_index"), to: "people_name_index")
  """
  def rename(%Table{} = table_current, to: %Table{} = table_new) do
    Runner.execute({:rename, __prefix__(table_current), __prefix__(table_new)})
    table_new
  end

  def rename(%Index{} = current_index, to: new_name) do
    Runner.execute({:rename, __prefix__(current_index), new_name})
    %{current_index | name: new_name}
  end

  @doc """
  Renames a column.

  Note that this occurs outside of the `alter` statement.

  ## Examples

      rename table("posts"), :title, to: :summary
  """
  def rename(%Table{} = table, current_column, to: new_column)
      when is_atom(current_column) and is_atom(new_column) do
    Runner.execute({:rename, __prefix__(table), current_column, new_column})
    table
  end

  @doc """
  Generates a fragment to be used as a default value.

  ## Examples

      create table("posts") do
        add :inserted_at, :naive_datetime, default: fragment("now()")
      end
  """
  def fragment(expr) when is_binary(expr) do
    {:fragment, expr}
  end

  @doc """
  Adds `:inserted_at` and `:updated_at` timestamp columns.

  Those columns are of `:naive_datetime` type. A list of `opts` can be given
  to customize the generated fields.

  Following options will override the repo configuration specified by
  `:migration_timestamps` option.

  ## Options

    * `:inserted_at` - the name of the column for storing insertion times.
      Setting it to `false` disables the column.
    * `:updated_at` - the name of the column for storing last-updated-at times.
      Setting it to `false` disables the column.
    * `:type` - the type of the `:inserted_at` and `:updated_at` columns.
      Defaults to `:naive_datetime`.
    * `:default` - the columns' default value. It can be a string, number, empty
      list, list of strings, list of numbers, or a fragment generated by
      `fragment/1`.
    * `:null` - determines whether the column accepts null values. Defaults to
      `false`.

  """
  def timestamps(opts \\ []) when is_list(opts) do
    opts = Keyword.merge(Runner.repo_config(:migration_timestamps, []), opts)
    opts = Keyword.put_new(opts, :null, false)

    {type, opts} = Keyword.pop(opts, :type, :naive_datetime)
    {inserted_at, opts} = Keyword.pop(opts, :inserted_at, :inserted_at)
    {updated_at, opts} = Keyword.pop(opts, :updated_at, :updated_at)

    if inserted_at != false, do: add(inserted_at, type, opts)
    if updated_at != false, do: add(updated_at, type, opts)
  end

  @doc """
  Modifies the type of a column when altering a table.

  This command is not reversible unless the `:from` option is provided.
  When the `:from` option is set, the adapter will try to drop
  the corresponding foreign key constraints before modifying the type.
  Generally speaking, you want to pass the type and each option
  you are modifying to `:from`, so the column can be rolled back properly.
  However, note that `:from` cannot be used to modify primary keys,
  as those are generally trickier to revert.

  See `add/3` for more information on supported types.

  If you want to modify a column without changing its type,
  such as adding or dropping a null constraints, consider using
  the `execute/2` command with the relevant SQL command instead
  of `modify/3`, if supported by your database. This may avoid
  redundant type updates and be more efficient, as an unnecessary
  type update can lock the table, even if the type actually
  doesn't change.

  ## Examples

      alter table("posts") do
        modify :title, :text
      end

      # Self rollback when using the :from option
      alter table("posts") do
        modify :title, :text, from: :string
      end

      # Modify column with rollback options
      alter table("posts") do
        modify :title, :text, null: false, from: {:string, null: true}
      end

      # Modify the :on_delete option of an existing foreign key
      alter table("comments") do
        modify :post_id, references(:posts, on_delete: :delete_all),
          from: references(:posts, on_delete: :nothing)
      end

  ## Options

    * `:null` - determines whether the column accepts null values. If this option is
      not set, the nullable behaviour of the underlying column is not modified.
    * `:default` - changes the default value of the column.
    * `:from` - specifies the current type and options of the column.
    * `:size` - specifies the size of the type (for example, the number of characters).
      The default is no size.
    * `:precision` - the precision for a numeric type. Required when `:scale` is
      specified.
    * `:scale` - the scale of a numeric type. Defaults to `0`.
    * `:comment` - adds a comment to the modified column.
    * `:collation` - the collation of the text type.
  """
  def modify(column, type, opts \\ []) when is_atom(column) and is_list(opts) do
    validate_precision_opts!(opts, column)
    validate_type!(type)
    Runner.subcommand({:modify, column, type, opts})
  end

  @doc """
  Removes a column when altering a table.

  This command is not reversible as Ecto does not know what type it should add
  the column back as. See `remove/3` as a reversible alternative.

  ## Examples

      alter table("posts") do
        remove :title
      end

  """
  def remove(column) when is_atom(column) do
    Runner.subcommand({:remove, column})
  end

  @doc """
  Removes a column in a reversible way when altering a table.

  `type` and `opts` are exactly the same as in `add/3`, and
  they are used when the command is reversed.

  If the `type` value is a `%Reference{}`, it is used to remove the constraint.

  ## Examples

      alter table("posts") do
        remove :title, :string, default: ""
      end

  """
  def remove(column, type, opts \\ []) when is_atom(column) do
    validate_type!(type)
    Runner.subcommand({:remove, column, type, opts})
  end

  @doc """
  Removes a column if the column exists.

  This command is not reversible as Ecto does not know whether or not the column existed before the removal attempt.

  ## Examples

      alter table("posts") do
        remove_if_exists :title
      end

  """
  def remove_if_exists(column) when is_atom(column) do
    Runner.subcommand({:remove_if_exists, column})
  end

  @doc """
  Removes a column if the column exists.

  If the type is a reference, removes the foreign key constraint for the reference first, if it exists.

  This command is not reversible as Ecto does not know whether or not the column existed before the removal attempt.

  ## Examples

      alter table("posts") do
        remove_if_exists :author_id, references(:authors)
      end

  """
  def remove_if_exists(column, type) when is_atom(column) do
    validate_type!(type)
    Runner.subcommand({:remove_if_exists, column, type})
  end

  @doc ~S"""
  Defines a foreign key.

  By default it assumes you are linking to the referenced table
  via its primary key with name `:id`. If you are using a non-default
  key setup (e.g. using `uuid` type keys) you must ensure you set the
  options, such as `:column` and `:type`, to match your target key.

  ## Examples

      create table("products") do
        add :group_id, references("groups")
      end

      create table("categories") do
        add :group_id, :integer
        # A composite foreign that points from categories (product_id, group_id)
        # to products (id, group_id)
        add :product_id, references("products", with: [group_id: :group_id])
      end

  ## Options

    * `:name` - The name of the underlying reference, which defaults to
      "#{table}_#{column}_fkey".
    * `:column` - The column name in the referenced table, which defaults to `:id`.
    * `:prefix` - The prefix for the reference. Defaults to the prefix
      defined by the block's `table/2` struct (the "products" table in
      the example above), or `nil`.
    * `:type` - The foreign key type, which defaults to `:bigserial`.
    * `:on_delete` - What to do if the referenced entry is deleted. May be
      `:nothing` (default), `:delete_all`, `:nilify_all`, `{:nilify, columns}`, `:default_all`, `{:default, columns}`
      or `:restrict`. `{:nilify, columns}` and `{:default, columns}` expect a list of atoms for `columns`
      and is not supported by all databases.
    * `:on_update` - What to do if the referenced entry is updated. May be
      `:nothing` (default), `:update_all`, `:nilify_all`, or `:restrict`.
    * `:validate` - Whether or not to validate the foreign key constraint on
       creation or not. Only available in PostgreSQL, and should be followed by
       a command to validate the foreign key in a following migration if false.
    * `:with` - defines additional keys to the foreign key in order to build
      a composite foreign key
    * `:match` - select if the match is `:simple`, `:partial`, or `:full`. This is
      [supported only by PostgreSQL](https://www.postgresql.org/docs/current/sql-createtable.html)
      at the moment.

  """
  def references(table, opts \\ [])

  def references(table, opts) when is_atom(table) do
    references(Atom.to_string(table), opts)
  end

  def references(table, opts) when is_binary(table) and is_list(opts) do
    reference_options = Keyword.take(opts, [:prefix])

    opts =
      foreign_key_repo_opts()
      |> Keyword.merge(opts)
      |> Keyword.put(:options, reference_options)

    reference = struct!(%Reference{table: table}, opts)
    check_on_delete!(reference.on_delete)
    check_on_update!(reference.on_update)

    reference
  end

  defp foreign_key_repo_opts() do
    case Runner.repo_config(:migration_primary_key, []) do
      false -> []
      opts -> opts
    end
    |> Keyword.take([:type])
    |> Keyword.merge(Runner.repo_config(:migration_foreign_key, []))
  end

  defp check_on_delete!(on_delete)
       when on_delete in [:nothing, :delete_all, :nilify_all, :default_all, :restrict],
       do: :ok

  defp check_on_delete!({option, columns})
       when option in [:nilify, :default] and is_list(columns) do
    unless Enum.all?(columns, &is_atom/1) do
      raise ArgumentError,
            "expected `columns` in `{#{inspect(option)}, columns}` to be a list of atoms, got: #{inspect(columns)}"
    end

    :ok
  end

  defp check_on_delete!(on_delete) do
    raise ArgumentError, "unknown :on_delete value: #{inspect(on_delete)}"
  end

  defp check_on_update!(on_update)
       when on_update in [:nothing, :update_all, :nilify_all, :restrict],
       do: :ok

  defp check_on_update!(on_update) do
    raise ArgumentError, "unknown :on_update value: #{inspect(on_update)}"
  end

  @doc ~S"""
  Defines a constraint (either a check constraint or an exclusion constraint)
  to be evaluated by the database when a row is inserted or updated.

  ## Examples

      create constraint("users", :price_must_be_positive, check: "price > 0")
      create constraint("size_ranges", :no_overlap, exclude: ~s|gist (int4range("from", "to", '[]') WITH &&)|)
      drop   constraint("products", "price_must_be_positive")

  ## Options

    * `:check` - A check constraint expression. Required when creating a check constraint.
    * `:exclude` - An exclusion constraint expression. Required when creating an exclusion constraint.
    * `:prefix` - The prefix for the table.
    * `:validate` - Whether or not to validate the constraint on creation (true by default). See the section below for more information
    * `:comment` - adds a comment to the constraint.


  ## Using `validate: false`

  Validation/Enforcement of a constraint is enabled by default, but disabling on constraint
  creation is supported by PostgreSQL, and MySQL, and can be done by setting `validate: false`.

  Setting `validate: false` as an option can be useful, as the creation of a constraint will cause
  a full table scan to check existing rows. The constraint will still be enforced for subsequent
  inserts and updates, but should then be updated in a following command or migration to enforce
  the new constraint.

  Validating / Enforcing the constraint in a later command, or migration, can be done like so:

  ```
    def change do
      # PostgreSQL
      execute "ALTER TABLE products VALIDATE CONSTRAINT price_must_be_positive", ""

      # MySQL
      execute "ALTER TABLE products ALTER CONSTRAINT price_must_be_positive ENFORCED", ""
    end
  ```

  See the [Safe Ecto Migrations guide](https://fly.io/phoenix-files/safe-ecto-migrations/) for an
  in-depth explanation of the benefits of this approach.
  """
  def constraint(table, name, opts \\ [])

  def constraint(table, name, opts) when is_atom(table) do
    constraint(Atom.to_string(table), name, opts)
  end

  def constraint(table, name, opts) when is_binary(table) and is_list(opts) do
    struct!(%Constraint{table: table, name: name}, opts)
  end

  @doc """
  Execute all changes specified by the migration so far.

  See [Executing and flushing](#module-executing-and-flushing).
  """
  defmacro flush do
    quote do
      if direction() == :down and not function_exported?(__MODULE__, :down, 0) do
        raise "calling flush() inside change when doing rollback is not supported."
      else
        Runner.flush()
      end
    end
  end

  # Validation helpers
  defp validate_type!(:datetime) do
    raise ArgumentError,
          "the :datetime type in migrations is not supported, " <>
            "please use :utc_datetime or :naive_datetime instead"
  end

  defp validate_type!(type) when is_atom(type) do
    case Atom.to_string(type) do
      "Elixir." <> _ ->
        raise_invalid_migration_type!(type)

      _ ->
        :ok
    end
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_atom(subtype) do
    validate_type!(subtype)
  end

  defp validate_type!({type, subtype}) when is_atom(type) and is_tuple(subtype) do
    for t <- Tuple.to_list(subtype), do: validate_type!(t)
  end

  defp validate_type!(%Reference{} = reference) do
    reference
  end

  defp validate_type!(type) do
    raise_invalid_migration_type!(type)
  end

  defp raise_invalid_migration_type!(type) do
    raise ArgumentError, """
    invalid migration type: #{inspect(type)}. Expected one of:

      * an atom, such as :string
      * a quoted atom, such as :"integer unsigned"
      * a tuple representing a composite type, such as {:array, :integer} or {:map, :string}
      * a reference, such as references(:users)

    Ecto types are automatically translated to database types. All other types
    are sent to the database as is.

    Types defined through Ecto.Type or Ecto.ParameterizedType aren't allowed,
    use their underlying types instead.
    """
  end

  defp validate_index_opts!(opts) when is_list(opts) do
    if opts[:nulls_distinct] != nil and opts[:unique] != true do
      raise ArgumentError, "the `nulls_distinct` option can only be used with unique indexes"
    end

    case Keyword.get_values(opts, :where) do
      [_, _ | _] ->
        raise ArgumentError,
              "only one `where` keyword is supported when declaring a partial index. " <>
                "To specify multiple conditions, write a single WHERE clause using AND between them"

      _ ->
        :ok
    end
  end

  defp validate_index_opts!(opts), do: opts

  defp validate_precision_opts!(opts, column) when is_list(opts) do
    if opts[:scale] && !opts[:precision] do
      raise ArgumentError, "column #{Atom.to_string(column)} is missing precision option"
    end
  end

  @doc false
  def __prefix__(%{prefix: prefix} = index_or_table) do
    runner_prefix = Runner.prefix()

    cond do
      is_nil(prefix) ->
        prefix = runner_prefix || Runner.repo_config(:migration_default_prefix, nil)
        %{index_or_table | prefix: prefix}

      is_nil(runner_prefix) or runner_prefix == to_string(prefix) ->
        index_or_table

      true ->
        raise Ecto.MigrationError,
          message:
            "the :prefix option `#{prefix}` does not match the migrator prefix `#{runner_prefix}`"
    end
  end

  @doc false
  def __primary_key__(table) do
    case table.primary_key do
      false ->
        false

      true ->
        case Runner.repo_config(:migration_primary_key, []) do
          false -> false
          opts when is_list(opts) -> pk_opts_to_tuple(opts)
        end

      opts when is_list(opts) ->
        pk_opts_to_tuple(opts)

      _ ->
        raise ArgumentError,
              ":primary_key option must be either a boolean or a keyword list of options"
    end
  end

  defp pk_opts_to_tuple(opts) do
    opts = Keyword.put(opts, :primary_key, true)
    {name, opts} = Keyword.pop(opts, :name, :id)
    {type, opts} = Keyword.pop(opts, :type, :bigserial)
    {name, type, opts}
  end
end
