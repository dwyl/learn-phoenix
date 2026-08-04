defmodule ElixirMake.Compiler do
  @moduledoc false

  @mac_error_msg """
  You need to have gcc and make installed. Try running the
  commands "gcc --version" and / or "make --version". If these programs
  are not installed, you will be prompted to install them.
  """

  @unix_error_msg """
  You need to have gcc and make installed. If you are using
  Ubuntu or any other Debian-based system, install the packages
  "build-essential". Also install "erlang-dev" package if not
  included in your Erlang/OTP version. If you're on Fedora, run
  "dnf group install 'Development Tools'".
  """

  @windows_error_msg ~S"""
  One option is to install a recent version of
  [Visual C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
  either manually or using [Chocolatey](https://chocolatey.org/) -
  `choco install VisualCppBuildTools`.

  After installing Visual C++ Build Tools, look in the "Program Files (x86)"
  directory and search for "Microsoft Visual Studio". Note down the full path
  of the folder with the highest version number. Open the "run" command and
  type in the following command (make sure that the path and version number
  are correct):

      cmd /K "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat" amd64

  This should open up a command prompt with the necessary environment variables
  set, and from which you will be able to run the "mix compile", "mix deps.compile",
  and "mix test" commands.

  Another option is to install the Linux compatiblity tools from [MSYS2](https://www.msys2.org/).

  After installation start the msys64 bit terminal from the start menu and install the
  C/C++ compiler toolchain. E.g.:

    pacman -S --noconfirm pacman-mirrors pkg-config
    pacman -S --noconfirm --needed base-devel autoconf automake make libtool git \
      mingw-w64-x86_64-toolchain mingw-w64-x86_64-openssl mingw-w64-x86_64-libtool

  This will give you a compilation suite nearly compatible with Unix' standard tools.
  """

  def compile(args) do
    config = Mix.Project.config()
    Mix.shell().print_app()
    priv? = File.dir?("priv")
    Mix.Project.ensure_structure()
    make(config, args)

    # IF there was no priv before and now there is one, we assume
    # the user wants to copy it. If priv already existed and was
    # written to it, then it won't be copied if build_embedded is
    # set to true.
    if not priv? and File.dir?("priv") do
      Mix.Project.build_structure()
    end

    {:ok, []}
  end

  def make(config, task_args) do
    exec =
      System.get_env("MAKE") ||
        os_specific_executable(Keyword.get(config, :make_executable, :default))

    makefile = Keyword.get(config, :make_makefile, :default)
    targets = Keyword.get(config, :make_targets, [])
    env = Keyword.get(config, :make_env, %{})
    env = if is_function(env), do: env.(), else: env
    env = default_env(config, env)

    cwd = Keyword.get(config, :make_cwd, ".") |> Path.expand(File.cwd!())
    error_msg = Keyword.get(config, :make_error_message, :default) |> os_specific_error_msg()
    custom_args = Keyword.get(config, :make_args, [])

    if String.contains?(cwd, " ") do
      IO.warn("""
      the absolute path to the Makefile for this project contains spaces. \
      Make might not work properly if spaces are present in the path. \
      The absolute path is: #{inspect(cwd)}
      """)
    end

    base = exec |> Path.basename() |> Path.rootname()
    args = args_for_makefile(base, makefile) ++ targets ++ custom_args

    case cmd(exec, args, cwd, env, "--verbose" in task_args) do
      0 ->
        :ok

      exit_status ->
        raise_build_error(exec, exit_status, error_msg)
    end
  end

  # Runs `exec [args]` in `cwd` and prints the stdout and stderr in real time,
  # as soon as `exec` prints them (using `IO.Stream`).
  defp cmd(exec, args, cwd, env, verbose?) do
    opts = [
      # There is no guarantee the command will return valid UTF-8,
      # especially on Windows, so don't try to interpret the stream
      into: IO.binstream(:stdio, :line),
      stderr_to_stdout: true,
      cd: cwd,
      env: env
    ]

    if verbose? do
      print_verbose_info(exec, args)
    end

    {%IO.Stream{}, status} = System.cmd(find_executable(exec), args, opts)
    status
  end

  defp find_executable(exec) do
    System.find_executable(exec) ||
      Mix.raise("""
      "#{exec}" not found in the path. If you have set the MAKE environment variable, \
      please make sure it is correct.
      """)
  end

  defp raise_build_error(exec, exit_status, error_msg) do
    Mix.raise(~s{Could not compile with "#{exec}" (exit status: #{exit_status}).\n} <> error_msg)
  end

  defp os_specific_executable(exec) when is_binary(exec) do
    exec
  end

  defp os_specific_executable(:default) do
    case :os.type() do
      {:win32, _} ->
        cond do
          System.find_executable("nmake") -> "nmake"
          System.find_executable("make") -> "make"
          true -> "nmake"
        end

      {:unix, type} when type in [:freebsd, :openbsd, :netbsd, :dragonfly] ->
        "gmake"

      _ ->
        "make"
    end
  end

  defp os_specific_error_msg(msg) when is_binary(msg) do
    msg
  end

  defp os_specific_error_msg(:default) do
    case :os.type() do
      {:unix, :darwin} -> @mac_error_msg
      {:unix, _} -> @unix_error_msg
      {:win32, _} -> @windows_error_msg
      _ -> ""
    end
  end

  # Returns a list of command-line args to pass to make (or nmake/gmake) in
  # order to specify the makefile to use.
  defp args_for_makefile("nmake", :default), do: ["/F", "Makefile.win"]
  defp args_for_makefile("nmake", makefile), do: ["/F", makefile]
  defp args_for_makefile(_, :default), do: []
  defp args_for_makefile(_, makefile), do: ["-f", makefile]

  defp print_verbose_info(exec, args) do
    args =
      Enum.map_join(args, " ", fn arg ->
        if String.contains?(arg, " "), do: inspect(arg), else: arg
      end)

    Mix.shell().info("Compiling with make: #{exec} #{args}")
  end

  # Returns a map of default environment variables
  # Defaults may be overwritten.
  defp default_env(config, default_env) do
    root_dir = :code.root_dir()
    erl_interface_dir = Path.join(root_dir, "usr")
    erts_dir = Path.join(root_dir, "erts-#{:erlang.system_info(:version)}")
    erts_include_dir = Path.join(erts_dir, "include")
    erl_ei_lib_dir = Path.join(erl_interface_dir, "lib")
    erl_ei_include_dir = Path.join(erl_interface_dir, "include")

    Map.merge(
      %{
        # Don't use Mix.target/0 here for backwards compatibility
        "MIX_TARGET" => env("MIX_TARGET", "host"),
        "MIX_ENV" => to_string(Mix.env()),
        "MIX_BUILD_PATH" => Mix.Project.build_path(config),
        "MIX_APP_PATH" => Mix.Project.app_path(config),
        "MIX_COMPILE_PATH" => Mix.Project.compile_path(config),
        "MIX_CONSOLIDATION_PATH" => Mix.Project.consolidation_path(config),
        "MIX_DEPS_PATH" => Mix.Project.deps_path(config),
        "MIX_MANIFEST_PATH" => Mix.Project.manifest_path(config),

        # Rebar naming
        "ERL_EI_LIBDIR" => env("ERL_EI_LIBDIR", erl_ei_lib_dir),
        "ERL_EI_INCLUDE_DIR" => env("ERL_EI_INCLUDE_DIR", erl_ei_include_dir),

        # erlang.mk naming
        "ERTS_INCLUDE_DIR" => env("ERTS_INCLUDE_DIR", erts_include_dir),
        "ERL_INTERFACE_LIB_DIR" => env("ERL_INTERFACE_LIB_DIR", erl_ei_lib_dir),
        "ERL_INTERFACE_INCLUDE_DIR" => env("ERL_INTERFACE_INCLUDE_DIR", erl_ei_include_dir),

        # Disable default erlang values
        "BINDIR" => nil,
        "ROOTDIR" => nil,
        "PROGNAME" => nil,
        "EMU" => nil
      },
      default_env
    )
  end

  defp env(var, default) do
    System.get_env(var) || default
  end
end
