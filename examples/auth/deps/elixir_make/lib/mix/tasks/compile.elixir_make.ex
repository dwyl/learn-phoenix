defmodule Mix.Tasks.Compile.ElixirMake do
  @moduledoc """
  Runs `make` in the current project.

  This task runs `make` in the current project; any output coming from `make` is
  printed in real-time on stdout.

  ## Configuration

  This compiler can be configured through the return value of the `project/0`
  function in `mix.exs`; for example:

      def project() do
        [app: :myapp,
         make_executable: "make",
         make_makefile: "Othermakefile",
         compilers: [:elixir_make] ++ Mix.compilers,
         deps: deps()]
      end

  The following options are available:

    * `:make_executable` - (binary or `:default`) it's the executable to use as the
      `make` program. If not provided or if `:default`, it defaults to `"nmake"`
      on Windows, `"gmake"` on FreeBSD, OpenBSD and NetBSD, and `"make"` on everything
      else. You can, for example, customize which executable to use on a
      specific OS and use `:default` for every other OS. If the `MAKE`
      environment variable is present, that is used as the value of this option.

    * `:make_makefile` - (binary or `:default`) it's the Makefile to
      use. Defaults to `"Makefile"` for Unix systems and `"Makefile.win"` for
      Windows systems if not provided or if `:default`.

    * `:make_targets` - (list of binaries) it's the list of Make targets that
      should be run. Defaults to `[]`, meaning `make` will run the first target.

    * `:make_clean` - (list of binaries) it's a list of Make targets to be run
      when `mix clean` is run. It's only run if a non-`nil` value for
      `:make_clean` is provided. Defaults to `nil`.

    * `:make_cwd` - (binary) it's the directory where `make` will be run,
      relative to the root of the project.

    * `:make_env` - (map of binary to binary) it's a map of extra environment
      variables to be passed to `make`. You can also pass a function in here in
      case `make_env` needs access to things that are not available during project
      setup; the function should return a map of binary to binary. Many default
      environment variables are set, see section below

    * `:make_error_message` - (binary or `:default`) it's a custom error message
      that can be used to give instructions as of how to fix the error (e.g., it
      can be used to suggest installing `gcc` if you're compiling a C
      dependency).

    * `:make_args` - (list of binaries) it's a list of extra arguments to be passed.

  The following options configure precompilation:

    * `:make_precompiler` - a two-element tuple with the precompiled type
      and module to use. The precompile type is either `:nif` or `:port`
      and then the precompilation module. If the type is a `:nif`, it looks
      for a DDL or a shared object as precompilation target given by
      `:make_precompiler_filename` and the current NIF version is part of
      the precompiled archive. If `:port`, it looks for an executable with
      `:make_precompiler_filename`.

    * `:make_precompiler_url` - the download URL template. Defaults to none.
      Required when `make_precompiler` is set.

    * `:make_precompiler_filename` - the filename of the compiled artefact
      without its extension. Defaults to the app name.

    * `:make_precompiler_downloader` - a module implementing the `ElixirMake.Downloader`
      behaviour. You can use this to customize how the precompiled artefacts
      are downloaded, for example, to add HTTP authentication or to download
      from an SFTP server. The default implementation uses `:httpc`.

    * `:make_force_build` - if build should be forced even if precompiled artefacts
      are available. Defaults to true if the app has a `-dev` version flag.

  See [the Precompilation guide](PRECOMPILATION_GUIDE.md) for more information.

  ## Default environment variables

  There are also several default environment variables set:

    * `MIX_TARGET`
    * `MIX_ENV`
    * `MIX_BUILD_PATH` - same as `Mix.Project.build_path/0`
    * `MIX_APP_PATH` - same as `Mix.Project.app_path/0`
    * `MIX_COMPILE_PATH` - same as `Mix.Project.compile_path/0`
    * `MIX_CONSOLIDATION_PATH` - same as `Mix.Project.consolidation_path/0`
    * `MIX_DEPS_PATH` - same as `Mix.Project.deps_path/0`
    * `MIX_MANIFEST_PATH` - same as `Mix.Project.manifest_path/0`
    * `ERL_EI_LIBDIR`
    * `ERL_EI_INCLUDE_DIR`
    * `ERTS_INCLUDE_DIR`
    * `ERL_INTERFACE_LIB_DIR`
    * `ERL_INTERFACE_INCLUDE_DIR`

  These may also be overwritten with the `make_env` option.

  ## Compilation artifacts and working with priv directories

  Generally speaking, compilation artifacts are written to the `priv`
  directory, as that the only directory, besides `ebin`, which are
  available to Erlang/OTP applications.

  However, note that Mix projects supports the `:build_embedded`
  configuration, which controls if assets in the `_build` directory
  are symlinked (when `false`, the default) or copied (`true`).
  In order to support both options for `:build_embedded`, it is
  important to follow the given guidelines:

    * The "priv" directory must not exist in the source code
    * The Makefile should copy any artifact to `$MIX_APP_PATH/priv`
      or, even better, to `$MIX_APP_PATH/priv/$MIX_TARGET`
    * If there are static assets, the Makefile should copy them over
      from a directory at the project root (not named "priv")

  """

  use Mix.Task
  alias ElixirMake.Artefact

  @recursive true

  @doc false
  def run(args) do
    if function_exported?(Mix, :ensure_application!, 1) do
      Mix.ensure_application!(:inets)
      Mix.ensure_application!(:ssl)
      Mix.ensure_application!(:crypto)
    end

    config = Mix.Project.config()
    app = config[:app]
    version = config[:version]

    force_build =
      pre_release?(version) or Keyword.get(config, :make_force_build, false) or
        Keyword.get(Application.get_env(:elixir_make, :force_build, []), app, false)

    {precompiler_type, precompiler} = config[:make_precompiler] || {nil, nil}

    cond do
      precompiler == nil ->
        ElixirMake.Compiler.compile(args)

      force_build == true ->
        precompiler.build_native(args)

      true ->
        rootname = config[:make_precompiler_filename] || "#{app}"

        extname =
          case {precompiler_type, :os.type()} do
            {:nif, {:win32, _}} -> ".dll"
            {:nif, _} -> ".so"
            {:port, {:win32, _}} -> ".exe"
            {:port, _} -> ""
            {_, _} -> raise_unknown_precompiler_type(precompiler_type)
          end

        app_priv = Path.join(Mix.Project.app_path(config), "priv")
        load_path = Path.join(app_priv, rootname <> extname)

        with false <- File.exists?(load_path),
             {:error, message} <- download_or_reuse_nif(config, precompiler, app_priv) do
          recover =
            case message do
              {:unavailable_target, current_target, _description} ->
                if function_exported?(precompiler, :unavailable_target, 1) do
                  precompiler.unavailable_target(current_target)
                else
                  :compile
                end

              _ ->
                Mix.shell().error("""
                Error happened while installing #{app} from precompiled binary: #{inspect(message)}.

                Attempting to compile #{app} from source...\
                """)

                :compile
            end

          case recover do
            :compile -> precompiler.build_native(args)
            :ignore -> {:ok, []}
          end
        else
          _ -> {:ok, []}
        end
    end
  end

  defp raise_unknown_precompiler_type(precompiler_type) do
    Mix.raise("Unknown precompiler type: #{inspect(precompiler_type)} (expected :nif or :port)")
  end

  # This is called by Elixir when `mix clean` runs
  # and `:elixir_make` is in the list of compilers.
  @doc false
  def clean() do
    config = Mix.Project.config()
    {clean_targets, config} = Keyword.pop(config, :make_clean)

    if clean_targets do
      config
      |> Keyword.put(:make_targets, clean_targets)
      |> ElixirMake.Compiler.make([])
    end
  end

  defp pre_release?(version) do
    "dev" in Version.parse!(version).pre
  end

  defp download_or_reuse_nif(config, precompiler, app_priv) do
    nif_version = "#{:erlang.system_info(:nif_version)}"

    case Artefact.current_target_url(config, precompiler, nif_version) do
      {:ok, target, nif_version_to_use, url} ->
        archived_fullpath = Artefact.archive_path(config, target, nif_version_to_use)

        unless File.exists?(archived_fullpath) do
          Mix.shell().info("Downloading precompiled NIF to #{archived_fullpath}")

          with {:ok, archived_data} <- Artefact.download(config, url) do
            File.mkdir_p(Path.dirname(archived_fullpath))
            File.write(archived_fullpath, archived_data)
          end
        end

        Artefact.verify_and_decompress(archived_fullpath, app_priv)

      {:error, msg} ->
        {:error, msg}
    end
  end
end
