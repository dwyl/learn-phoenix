defmodule Mix.Tasks.Esbuild.Install do
  @moduledoc """
  Installs esbuild under `_build`.

  ```bash
  $ mix esbuild.install
  $ mix esbuild.install --if-missing
  ```

  By default, it installs #{Esbuild.latest_version()} but you
  can configure it in your config files, such as:

      config :esbuild, :version, "#{Esbuild.latest_version()}"

  ## Options

      * `--runtime-config` - load the runtime configuration
        before executing command

      * `--if-missing` - install only if the given version
        does not exist
  """

  @shortdoc "Installs esbuild under _build"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    valid_options = [runtime_config: :boolean, if_missing: :boolean]

    case OptionParser.parse_head!(args, strict: valid_options) do
      {opts, []} ->
        if opts[:runtime_config] do
          Mix.Task.run("app.config")
        else
          Mix.Task.run("loadpaths")
        end

        if opts[:if_missing] && latest_version?() do
          :ok
        else
          if function_exported?(Mix, :ensure_application!, 1) do
            Mix.ensure_application!(:inets)
            Mix.ensure_application!(:ssl)
          end

          Esbuild.install()
        end

      {_, _} ->
        Mix.raise("""
        Invalid arguments to esbuild.install, expected one of:

            mix esbuild.install
            mix esbuild.install --runtime-config
            mix esbuild.install --if-missing
        """)
    end
  end

  defp latest_version?() do
    version = Esbuild.configured_version()
    match?({:ok, ^version}, Esbuild.bin_version())
  end
end
