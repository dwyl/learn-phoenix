defmodule Mix.Tasks.Tailwind do
  @moduledoc """
  Invokes tailwind with the given args.

  Usage:

      $ mix tailwind TASK_OPTIONS PROFILE TAILWIND_ARGS

  Example:

      $ mix tailwind default --minify --input=css/app.css \
        --output=../priv/static/assets/app.css \

  If Tailwind is not installed, it is automatically downloaded.
  Note the arguments given to this task will be appended
  to any configured arguments.

  If using Tailwind v3, you'd also pass the `--config=tailwind.config.js`
  flag pointing to your Tailwind configuration. In Tailwind v4, the
  configuration happens with the input CSS file.

  ## Options

    * `--runtime-config` - load the runtime configuration
      before executing command

  Note flags to control this Mix task must be given before the
  profile:

      $ mix tailwind --runtime-config default
  """

  @shortdoc "Invokes tailwind with the profile and args"
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
      Application.ensure_all_started(:tailwind)
    end

    Mix.Task.reenable("tailwind")
    install_and_run(remaining_args)
  end

  defp install_and_run([profile | args] = all) do
    case Tailwind.install_and_run(String.to_atom(profile), args) do
      0 -> :ok
      status -> Mix.raise("`mix tailwind #{Enum.join(all, " ")}` exited with #{status}")
    end
  end

  defp install_and_run([]) do
    Mix.raise("`mix tailwind` expects the profile as argument")
  end
end
