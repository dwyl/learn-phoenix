defmodule Phoenix.LiveReloader.Application do
  use Application
  require Logger

  alias Phoenix.LiveReloader.WebConsoleLogger

  def start(_type, _args) do
    # note we always attach and start the logger as :phoenix_live_reload should only
    # be started in dev via user's `only: :dev` entry.

    # the deps paths are read by the channel when getting the full_path for
    # opening the configured PLUG_EDITOR
    :persistent_term.put(:phoenix_live_reload_deps_paths, deps_paths())

    children = [
      Registry.child_spec(name: WebConsoleLogger.registry(), keys: :duplicate),
      WebConsoleLogger,
      %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def start_link do
    dirs = Application.get_env(:phoenix_live_reload, :dirs, [""])
    backend_opts = Application.get_env(:phoenix_live_reload, :backend_opts, [])

    opts =
      [
        name: :phoenix_live_reload_file_monitor,
        dirs: Enum.map(dirs, &Path.absname/1)
      ] ++ backend_opts

    opts =
      if backend = Application.get_env(:phoenix_live_reload, :backend) do
        [backend: backend] ++ opts
      else
        opts
      end

    case FileSystem.start_link(opts) do
      {:ok, pid} ->
        {:ok, pid}

      other ->
        Logger.warning("""
        Could not start Phoenix live-reload because we cannot listen to the file system.
        You don't need to worry! This is an optional feature used during development to
        refresh your browser when you save files and it does not affect production.
        """)

        other
    end
  end

  defp deps_paths do
    # TODO: Use `Code.loaded?` on Elixir v1.15+
    if :erlang.module_loaded(Mix.Project) do
      for {app, path} <- Mix.Project.deps_paths(), into: %{}, do: {to_string(app), path}
    else
      %{}
    end
  end
end
