defmodule Mix.Tasks.Tailwind.Install do
  @moduledoc """
  Installs Tailwind executable and assets.

      $ mix tailwind.install
      $ mix tailwind.install --if-missing

  By default, it installs #{Tailwind.latest_version()} but you
  can configure it in your config files, such as:

      config :tailwind, :version, "#{Tailwind.latest_version()}"

  To install the Tailwind binary from a custom URL (e.g. if your platform isn't
  officially supported by Tailwind), you can supply a third party path to the
  binary (beware that we cannot guarantee the compatibility of any third party
  executable):

  ```bash
  $ mix tailwind.install https://people.freebsd.org/~dch/pub/tailwind/v3.2.6/tailwindcss-freebsd-x64
  ```

  ## Options

    * `--runtime-config` - load the runtime configuration
      before executing command

    * `--if-missing` - install only if the given version
      does not exist

  """

  @shortdoc "Installs Tailwind executable"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    valid_options = [runtime_config: :boolean, if_missing: :boolean]

    {opts, base_url} =
      case OptionParser.parse_head!(args, strict: valid_options) do
        {opts, []} ->
          {opts, Tailwind.default_base_url()}

        {opts, [base_url]} ->
          {opts, base_url}

        {_, _} ->
          Mix.raise("""
          Invalid arguments to tailwind.install, expected one of:

              mix tailwind.install
              mix tailwind.install 'https://github.com/tailwindlabs/tailwindcss/releases/download/v$version/tailwindcss-$target'
              mix tailwind.install --runtime-config
              mix tailwind.install --if-missing
          """)
      end

    if opts[:runtime_config], do: Mix.Task.run("app.config")

    if opts[:if_missing] && latest_version?() do
      :ok
    else
      if function_exported?(Mix, :ensure_application!, 1) do
        Mix.ensure_application!(:inets)
        Mix.ensure_application!(:ssl)
      end

      Mix.Task.run("loadpaths")
      Tailwind.install(base_url)
    end
  end

  defp latest_version?() do
    version = Tailwind.configured_version()
    match?({:ok, ^version}, Tailwind.bin_version())
  end
end
