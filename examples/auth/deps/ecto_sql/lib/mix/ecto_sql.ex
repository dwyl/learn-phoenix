defmodule Mix.EctoSQL do
  @moduledoc false

  @doc """
  Ensures the given repository's migrations paths exists on the file system.
  """
  @spec ensure_migrations_paths(Ecto.Repo.t(), Keyword.t()) :: [String.t()]
  def ensure_migrations_paths(repo, opts) do
    paths = Keyword.get_values(opts, :migrations_path)
    paths = if paths == [], do: [Path.join(source_repo_priv(repo), "migrations")], else: paths

    if not Mix.Project.umbrella?() do
      for path <- paths, not File.dir?(path) do
        raise_missing_migrations(Path.relative_to_cwd(path), repo)
      end
    end

    paths
  end

  defp raise_missing_migrations(path, repo) do
    Mix.raise("""
    Could not find migrations directory #{inspect(path)}
    for repo #{inspect(repo)}.

    This may be because you are in a new project and the
    migration directory has not been created yet. Creating an
    empty directory at the path above will fix this error.

    If you expected existing migrations to be found, please
    make sure your repository has been properly configured
    and the configured path exists.
    """)
  end

  @doc """
  Returns the private repository path relative to the source.
  """
  def source_repo_priv(repo) do
    config = repo.config()
    priv = config[:priv] || "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"
    app = Keyword.fetch!(config, :otp_app)
    Path.join(Mix.Project.deps_paths()[app] || File.cwd!(), priv)
  end
end
