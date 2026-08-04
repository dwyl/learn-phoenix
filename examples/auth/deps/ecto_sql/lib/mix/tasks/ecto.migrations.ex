defmodule Mix.Tasks.Ecto.Migrations do
  use Mix.Task
  import Mix.Ecto
  import Mix.EctoSQL

  @shortdoc "Displays the repository migration status"

  @aliases [
    r: :repo
  ]

  @switches [
    repo: [:keep, :string],
    no_compile: :boolean,
    no_deps_check: :boolean,
    migrations_path: :keep,
    prefix: :string
  ]

  @moduledoc """
  Displays the up / down migration status for the given repository.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  By default, migrations are expected at "priv/YOUR_REPO/migrations"
  directory of the current application but it can be configured
  by specifying the `:priv` key under the repository configuration.

  If the repository has not been started yet, one will be
  started outside our application supervision tree and shutdown
  afterwards.

  ## Examples

      $ mix ecto.migrations
      $ mix ecto.migrations -r Custom.Repo

  ## Command line options

    * `--migrations-path` - the path to load the migrations from, defaults to
      `"priv/repo/migrations"`. This option may be given multiple times in which
      case the migrations are loaded from all the given directories and sorted as
      if they were in the same one.

      Note, if you have previously run migrations from paths `a/` and `b/`, and now
      run `mix ecto.migrations --migrations-path a/` (omitting path `b/`), the
      migrations from the path `b/` will be shown in the output as `** FILE NOT FOUND **`.

    * `--no-compile` - does not compile applications before running

    * `--no-deps-check` - does not check dependencies before running

    * `--prefix` - the prefix to check migrations on

    * `-r`, `--repo` - the repo to obtain the status for

  """

  @impl true
  def run(args, migrations \\ &Ecto.Migrator.migrations/3, puts \\ &IO.puts/1) do
    repos = parse_repo(args)
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    for repo <- repos do
      ensure_repo(repo, args)
      paths = ensure_migrations_paths(repo, opts)

      case Ecto.Migrator.with_repo(repo, &migrations.(&1, paths, opts), mode: :temporary) do
        {:ok, repo_status, _} ->
          puts.(
            """

            Repo: #{inspect(repo)}

              Status    Migration ID    Migration Name
            --------------------------------------------------
            """ <>
              Enum.map_join(repo_status, "\n", fn {status, number, description} ->
                "  #{format(status, 10)}#{format(number, 16)}#{description}"
              end) <> "\n"
          )

        {:error, error} ->
          Mix.raise("Could not start repo #{inspect(repo)}, error: #{inspect(error)}")
      end
    end

    :ok
  end

  defp format(content, pad) do
    content
    |> to_string
    |> String.pad_trailing(pad)
  end
end
