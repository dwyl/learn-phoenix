defmodule Mix.Tasks.Ecto.Load do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Loads previously dumped database structure"
  @default_opts [force: false, quiet: false]

  @aliases [
    d: :dump_path,
    f: :force,
    q: :quiet,
    r: :repo
  ]

  @switches [
    dump_path: :string,
    force: :boolean,
    quiet: :boolean,
    repo: [:string, :keep],
    no_compile: :boolean,
    no_deps_check: :boolean,
    skip_if_loaded: :boolean
  ]

  @moduledoc """
  Loads the current environment's database structure for the
  given repository from a previously dumped structure file.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  This task needs some shell utility to be present on the machine
  running the task.

   Database   | Utility needed
   :--------- | :-------------
   PostgreSQL | psql
   MySQL      | mysql

  ## Example

      $ mix ecto.load

  ## Command line options

    * `-r`, `--repo` - the repo to load the structure info into
    * `-d`, `--dump-path` - the path of the dump file to load from
    * `-q`, `--quiet` - run the command quietly
    * `-f`, `--force` - do not ask for confirmation when loading data.
      Configuration is asked only when `:start_permanent` is set to true
      (typically in production)
    * `--no-compile` - does not compile applications before loading
    * `--no-deps-check` - does not check dependencies before loading
    * `--skip-if-loaded` - does not load the dump file if the repo has the migrations table up

  """

  @impl true
  def run(args, table_exists? \\ &Ecto.Adapters.SQL.table_exists?/3) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Keyword.merge(@default_opts, opts)
    opts = if opts[:quiet], do: Keyword.put(opts, :log, false), else: opts

    Enum.each(parse_repo(args), fn repo ->
      ensure_repo(repo, args)

      ensure_implements(
        repo.__adapter__(),
        Ecto.Adapter.Structure,
        "load structure for #{inspect(repo)}"
      )

      {migration_repo, source} =
        Ecto.Migration.SchemaMigration.get_repo_and_source(repo, repo.config())

      {:ok, loaded?, _} =
        Ecto.Migrator.with_repo(migration_repo, table_exists_closure(table_exists?, source, opts))

      for repo <- Enum.uniq([repo, migration_repo]) do
        cond do
          loaded? and opts[:skip_if_loaded] ->
            :ok

          (skip_safety_warnings?() and not loaded?) or opts[:force] or confirm_load(repo, loaded?) ->
            load_structure(repo, opts)

          true ->
            :ok
        end
      end
    end)
  end

  defp table_exists_closure(fun, source, opts) when is_function(fun, 3) do
    &fun.(&1, source, opts)
  end

  defp table_exists_closure(fun, source, _opts) when is_function(fun, 2) do
    &fun.(&1, source)
  end

  defp skip_safety_warnings? do
    Mix.Project.config()[:start_permanent] != true
  end

  defp confirm_load(repo, false) do
    Mix.shell().yes?(
      "Are you sure you want to load a new structure for #{inspect(repo)}? Any existing data in this repo may be lost."
    )
  end

  defp confirm_load(repo, true) do
    Mix.shell().yes?("""
    It looks like a structure was already loaded for #{inspect(repo)}. Any attempt to load it again might fail.
    Are you sure you want to proceed?
    """)
  end

  defp load_structure(repo, opts) do
    config = Keyword.merge(repo.config(), opts)
    start_time = System.system_time()

    case repo.__adapter__().structure_load(source_repo_priv(repo), config) do
      {:ok, location} ->
        unless opts[:quiet] do
          elapsed =
            System.convert_time_unit(System.system_time() - start_time, :native, :microsecond)

          Mix.shell().info(
            "The structure for #{inspect(repo)} has been loaded from #{location} in #{format_time(elapsed)}"
          )
        end

      {:error, term} when is_binary(term) ->
        Mix.raise("The structure for #{inspect(repo)} couldn't be loaded: #{term}")

      {:error, term} ->
        Mix.raise("The structure for #{inspect(repo)} couldn't be loaded: #{inspect(term)}")
    end
  end

  defp format_time(microsec) when microsec < 1_000, do: "#{microsec} μs"
  defp format_time(microsec) when microsec < 1_000_000, do: "#{div(microsec, 1_000)} ms"
  defp format_time(microsec), do: "#{Float.round(microsec / 1_000_000.0)} s"
end
