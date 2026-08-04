defmodule Phoenix.Ecto.CheckRepoStatus do
  @moduledoc """
  A plug that does some checks on your application repos.

  Checks if the storage is up (database is created) or if there are any pending migrations.
  Both checks can raise an error if the conditions are not met.

  ## Plug options

    * `:otp_app` - name of the application which the repos are fetched from
    * `:migration_paths` - a function that accepts a repo and returns a migration directory, or a list of migration directories, that is used to check for pending migrations
    * `:migration_lock` - the locking strategy used by the Ecto Adapter when checking for pending migrations. Set to `false` to disable migration locks.
    * `:prefix` - the prefix used to check for pending migrations.
    * `:skip_table_creation` - Ecto will not try to create the `schema_migrations` table automatically.  This is useful if you are connecting as a DB user without create permissions
  """

  @behaviour Plug

  alias Plug.Conn

  @migration_opts [:migration_lock, :prefix, :skip_table_creation]
  @compile {:no_warn_undefined, Ecto.Migrator}

  def init(opts) do
    Keyword.fetch!(opts, :otp_app)
    opts
  end

  def call(%Conn{} = conn, opts) do
    try do
      repos = Application.get_env(opts[:otp_app], :ecto_repos, [])

      for repo <- repos, Process.whereis(repo) do
        check_pending_migrations!(repo, opts) || check_storage_up!(repo)
      end

      conn
    rescue
      err in [Phoenix.Ecto.StorageNotCreatedError, Phoenix.Ecto.PendingMigrationError] ->
        Plug.Conn.WrapperError.reraise(conn, :error, err, __STACKTRACE__)
    end
  end

  defp check_storage_up!(repo) do
    try do
      adapter = repo.__adapter__()

      if Code.ensure_loaded?(adapter) && function_exported?(adapter, :storage_status, 1) do
        adapter.storage_status(repo.config())
      end
    rescue
      _ -> true
    else
      :down -> raise Phoenix.Ecto.StorageNotCreatedError, repo: repo
      _ -> true
    end
  end

  defp check_pending_migrations!(repo, opts) do
    dirs = migration_directories(repo, opts)

    migrations_fun =
      Keyword.get_lazy(opts, :mock_migrations_fn, fn ->
        if Code.ensure_loaded?(Ecto.Migrator),
          do: &Ecto.Migrator.migrations/3,
          else: fn _repo, _paths, _opts -> raise "to be rescued" end
      end)

    true = is_function(migrations_fun, 3)
    migration_opts = Keyword.take(opts, @migration_opts)

    try do
      repo
      |> migrations_fun.(dirs, migration_opts)
      |> Enum.any?(fn {status, _version, _migration} -> status == :down end)
    rescue
      _ -> false
    else
      true ->
        raise Phoenix.Ecto.PendingMigrationError,
          repo: repo,
          directories: dirs,
          migration_opts: migration_opts

      false ->
        true
    end
  end

  defp migration_directories(repo, opts) do
    case Keyword.fetch(opts, :migration_paths) do
      {:ok, migration_directories_fn} ->
        List.wrap(migration_directories_fn.(repo))

      :error ->
        try do
          [Ecto.Migrator.migrations_path(repo)]
        rescue
          _ -> []
        end
    end
  end
end
