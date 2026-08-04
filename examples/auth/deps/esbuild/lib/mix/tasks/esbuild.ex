defmodule Mix.Tasks.Esbuild do
  @moduledoc """
  Invokes esbuild with the given args.

  Usage:

      $ mix esbuild TASK_OPTIONS PROFILE ESBUILD_ARGS

  Example:

      $ mix esbuild default assets/js/app.js --bundle --minify --target=es2016 --outdir=priv/static/assets

  If esbuild is not installed, it is automatically downloaded.
  Note the arguments given to this task will be appended
  to any configured arguments.

  ## Options

    * `--runtime-config` - load the runtime configuration
      before executing command

  Note flags to control this Mix task must be given before the
  profile:

      $ mix esbuild --runtime-config default assets/js/app.js

  """

  @shortdoc "Invokes esbuild with the profile and args"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    switches = [runtime_config: :boolean]
    {opts, remaining_args} = OptionParser.parse_head!(args, switches: switches)

    if function_exported?(Mix, :ensure_application!, 1) do
      Mix.ensure_application!(:inets)
      Mix.ensure_application!(:ssl)
    end

    if opts[:runtime_config] do
      Mix.Task.run("app.config")
    else
      Mix.Task.run("loadpaths")
      Application.ensure_all_started(:esbuild)
    end

    Mix.Task.reenable("esbuild")
    install_and_run(remaining_args)
  end

  defp install_and_run([profile | args] = all) do
    case Esbuild.install_and_run(String.to_atom(profile), args) do
      0 -> :ok
      status -> Mix.raise("`mix esbuild #{Enum.join(all, " ")}` exited with #{status}")
    end
  end

  defp install_and_run([]) do
    Mix.raise("`mix esbuild` expects the profile as argument")
  end
end
