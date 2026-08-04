defmodule CCPrecompiler do
  @moduledoc """
  Precompile with existing crosscompiler in the system.
  """

  require Logger
  @behaviour ElixirMake.Precompiler

  # The default configuration for this precompiler module on linux systems.
  # It will detect for the following targets
  #   - x86_64-linux-gnu
  #   - i686-linux-gnu
  #   - aarch64-linux-gnu
  #   - armv7l-linux-gnueabihf
  #   - riscv64-linux-gnu
  #   - powerpc64le-linux-gnu
  #   - s390x-linux-gnu
  # by trying to find the corresponding executable, i.e.,
  #   - x86_64-linux-gnu-gcc
  #   - i686-linux-gnu-gcc
  #   - aarch64-linux-gnu-gcc
  #   - arm-linux-gnueabihf-gcc
  #   - riscv64-linux-gnu-gcc
  #   - powerpc64le-linux-gnu-gcc
  #   - s390x-linux-gnu-gcc
  # (this module will only try to find the CC executable, a step further
  # will be trying to compile a simple C/C++ program using them)
  @default_compilers %{
    {:unix, :linux} => %{
      "x86_64-linux-gnu" => "x86_64-linux-gnu-",
      "i686-linux-gnu" => "i686-linux-gnu-",
      "aarch64-linux-gnu" => "aarch64-linux-gnu-",
      "armv7l-linux-gnueabihf" => "arm-linux-gnueabihf-",
      "riscv64-linux-gnu" => "riscv64-linux-gnu-",
      "powerpc64le-linux-gnu" => "powerpc64le-linux-gnu-",
      "s390x-linux-gnu" => "s390x-linux-gnu-"
    },
    {:unix, :darwin} => %{
      "x86_64-apple-darwin" => {
        "gcc",
        "g++",
        "<%= cc %> -arch x86_64",
        "<%= cxx %> -arch x86_64"
      },
      "aarch64-apple-darwin" => {
        "gcc",
        "g++",
        "<%= cc %> -arch arm64",
        "<%= cxx %> -arch arm64"
      }
    },
    {:win32, :nt} => %{
      "x86_64-windows-msvc" => {"cl", "cl"}
    }
  }
  defp default_compilers, do: @default_compilers
  defp user_config, do: Mix.Project.config()[:cc_precompiler] || default_compilers()
  defp compilers, do: Access.get(user_config(), :compilers, default_compilers())

  defp compilers_current_os,
    do:
      {Access.get(compilers(), :os.type(), %{}), Access.get(default_compilers(), :os.type(), %{})}

  defp compilers_current_os_with_override do
    {compiler_map1, compiler_map2} = compilers_current_os()

    if Map.has_key?(compiler_map1, :include_default_ones) do
      include_default_ones = Map.get(compiler_map1, :include_default_ones, false)
      compiler_map1 = Map.delete(compiler_map1, :include_default_ones)

      if include_default_ones == true do
        Map.merge(compiler_map1, compiler_map2, fn _, _, user_override -> user_override end)
      else
        compiler_map1
      end
    else
      compiler_map1
    end
  end

  defp only_listed_targets, do: Access.get(user_config(), :only_listed_targets, false)
  defp exclude_current_target, do: Access.get(user_config(), :exclude_current_target, false)
  defp allow_missing_compiler, do: Access.get(user_config(), :allow_missing_compiler, false)

  @impl ElixirMake.Precompiler
  def current_target do
    current_target_from_env = current_target_from_env()

    if current_target_from_env do
      # overwrite current target triplet from environment variables
      {:ok, current_target_from_env}
    else
      current_target(:os.type())
    end
  end

  defp current_target_from_env do
    arch = System.get_env("TARGET_ARCH")
    os = System.get_env("TARGET_OS")
    abi = System.get_env("TARGET_ABI")

    if !Enum.all?([arch, os, abi], &Kernel.is_nil/1) do
      "#{arch}-#{os}-#{abi}"
    end
  end

  def current_target({:win32, _}) do
    processor_architecture =
      String.downcase(String.trim(System.get_env("PROCESSOR_ARCHITECTURE")))

    # https://docs.microsoft.com/en-gb/windows/win32/winprog64/wow64-implementation-details?redirectedfrom=MSDN
    partial_triplet =
      case processor_architecture do
        "amd64" ->
          "x86_64-windows-"

        "ia64" ->
          "ia64-windows-"

        "arm64" ->
          "aarch64-windows-"

        "x86" ->
          "x86-windows-"
      end

    {compiler, _} = :erlang.system_info(:c_compiler_used)

    case compiler do
      :msc ->
        {:ok, partial_triplet <> "msvc"}

      :gnuc ->
        {:ok, partial_triplet <> "gnu"}

      other ->
        {:ok, partial_triplet <> Atom.to_string(other)}
    end
  end

  def current_target({:unix, _}) do
    # get current target triplet from `:erlang.system_info/1`
    system_architecture = to_string(:erlang.system_info(:system_architecture))
    current = String.split(system_architecture, "-", trim: true)

    case length(current) do
      4 ->
        {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 2)}-#{Enum.at(current, 3)}"}

      3 ->
        case :os.type() do
          {:unix, :darwin} ->
            # could be something like aarch64-apple-darwin21.0.0
            # but we don't really need the last 21.0.0 part
            if String.match?(Enum.at(current, 2), ~r/^darwin.*/) do
              {:ok, "#{Enum.at(current, 0)}-#{Enum.at(current, 1)}-darwin"}
            else
              {:ok, system_architecture}
            end

          _ ->
            {:ok, system_architecture}
        end

      _ ->
        {:error, "cannot decide current target"}
    end
  end

  defp only_local do
    System.get_env("CC_PRECOMPILER_PRECOMPILE_ONLY_LOCAL") == "true"
  end

  @impl ElixirMake.Precompiler
  def all_supported_targets(:compile) do
    # this callback is expected to return a list of string for
    #   all supported targets by this precompiler. in this
    #   implementation, we will try to find a few crosscompilers
    #   available in the system.
    # Note that this implementation is mainly used for demonstration
    #   purpose, therefore the hardcoded compiler names are used in
    #   DEBIAN/Ubuntu Linux (as I only installed these ones at the
    #   time of writing this example)
    available_targets = find_all_available_targets()

    targets =
      case {only_local(), only_listed_targets(), current_target()} do
        {true, true, {:ok, current}} ->
          if Enum.member?(available_targets, current) do
            [current]
          else
            []
          end

        {true, _, {:error, err_msg}} ->
          Mix.raise(err_msg)

        {true, false, {:ok, current}} ->
          Enum.uniq([current] ++ available_targets)

        {false, true, _} ->
          available_targets

        {false, false, {:ok, current}} ->
          Enum.uniq([current] ++ available_targets)
      end

    if exclude_current_target() do
      case current_target() do
        {:ok, current} ->
          targets -- [current]

        _ ->
          targets
      end
    else
      targets
    end
  end

  @impl ElixirMake.Precompiler
  def all_supported_targets(:fetch) do
    Enum.map(compilers(), fn {os, compilers} ->
      Enum.map(Map.keys(compilers), fn key ->
        if key == :include_default_ones do
          Map.keys(default_compilers()[os])
        else
          key
        end
      end)
    end)
    |> List.flatten()
  end

  @impl ElixirMake.Precompiler
  def unavailable_target(_) do
    if only_listed_targets() do
      :ignore
    else
      :compile
    end
  end

  defp find_all_available_targets do
    compilers = compilers_current_os_with_override()

    compilers
    |> Map.keys()
    |> Enum.map(&find_available_compilers(&1, Map.get(compilers, &1)))
    |> Enum.reject(fn x -> x == nil end)
  end

  defp find_available_compilers(triplet, prefix) when is_binary(prefix) do
    if ensure_executable(["#{prefix}gcc", "#{prefix}g++"]) do
      Logger.debug("Found compiler for #{triplet}")
      triplet
    else
      Logger.debug("Compiler not found for #{triplet}")
      nil
    end
  end

  defp find_available_compilers(triplet, {cc, cxx}) when is_binary(cc) and is_binary(cxx) do
    if ensure_executable([cc, cxx]) do
      Logger.debug("Found compiler for #{triplet}")
      triplet
    else
      Logger.debug("Compiler not found for #{triplet}")
      nil
    end
  end

  defp find_available_compilers(triplet, {:script, _, _}) do
    triplet
  end

  defp find_available_compilers(triplet, {cc_executable, cxx_executable, _, _})
       when is_binary(cc_executable) and is_binary(cxx_executable) do
    if ensure_executable([cc_executable, cxx_executable]) do
      Logger.debug("Found compiler for #{triplet}")
      triplet
    else
      Logger.debug("Compiler not found for #{triplet}")
      nil
    end
  end

  defp find_available_compilers(triplet, invalid) do
    Mix.raise(
      "Invalid configuration for #{triplet}, expecting a string, 2-tuple or 4-tuple. Got `#{inspect(invalid)}`"
    )
  end

  defp ensure_executable(executable_list) when is_list(executable_list) do
    if allow_missing_compiler() do
      Enum.any?(executable_list, &System.find_executable/1)
    else
      Enum.all?(executable_list, &System.find_executable/1)
    end
  end

  @impl ElixirMake.Precompiler
  def build_native(args) do
    # In this callback we just build the NIF library natively,
    # and because this precompiler module is designed for NIF
    # libraries that use C/C++ as the main language with Makefile,
    # we can just call `ElixirMake.Precompiler.mix_compile(args)`
    #
    # It's also possible to forward this call to:
    #
    #   `precompile(args, elem(current_target(), 1))`
    #
    # This could be useful when the precompiler is using a universal
    # (cross-)compiler, say zig. in this way, the compiled binaries
    # (`mix compile`) will be consistent as the corresponding precompiled
    # one (with `mix elixir_make.precompile`)
    #
    # However, if you'd prefer to having the same behaviour for `mix compile`
    # then the following line is okay
    ElixirMake.Precompiler.mix_compile(args)
  end

  @impl ElixirMake.Precompiler
  def precompile(args, target) do
    # in this callback we compile the NIF library for a given target
    config = Mix.Project.config()
    app = config[:app]
    version = config[:version]
    priv_paths = config[:make_precompiler_priv_paths] || ["."]

    saved_cc = System.get_env("CC") || ""
    saved_cxx = System.get_env("CXX") || ""
    saved_cpp = System.get_env("CPP") || ""

    Logger.debug("Current compiling target: #{target}")

    cc_cxx = get_cc_and_cxx(target)

    # remove files in the lists
    app_priv = Path.join(Mix.Project.app_path(config), "priv")

    case priv_paths do
      ["."] ->
        File.rm_rf!(app_priv)

      _ ->
        for include <- priv_paths,
            file <- Path.wildcard(Path.join(app_priv, include)) do
          File.rm_rf(file)
        end
    end

    File.mkdir_p!(app_priv)

    case cc_cxx do
      {cc, cxx} ->
        System.put_env("CC", cc)
        System.put_env("CXX", cxx)
        System.put_env("CPP", cxx)

        System.put_env("CC_PRECOMPILER_CURRENT_TARGET", target)
        ElixirMake.Precompiler.mix_compile(args)

      {:script, module, custom_args} ->
        System.put_env("CC_PRECOMPILER_CURRENT_TARGET", target)

        Kernel.apply(module, :compile, [
          app,
          version,
          "#{:erlang.system_info(:nif_version)}",
          target,
          args,
          custom_args
        ])
    end

    System.put_env("CC", saved_cc)
    System.put_env("CXX", saved_cxx)
    System.put_env("CPP", saved_cpp)

    :ok
  end

  defp get_cc_and_cxx(triplet) do
    case Access.get(compilers_current_os_with_override(), triplet, nil) do
      nil ->
        cc = System.get_env("CC")
        cxx = System.get_env("CXX")
        cpp = System.get_env("CPP")

        case {cc, cxx, cpp} do
          {nil, _, _} ->
            {"gcc", "g++"}

          {_, nil, nil} ->
            {"gcc", "g++"}

          {_, _, nil} ->
            {cc, cxx}

          {_, nil, _} ->
            {cc, cpp}

          {_, _, _} ->
            {cc, cxx}
        end

      {cc, cxx} ->
        {cc, cxx}

      prefix when is_binary(prefix) ->
        {"#{prefix}gcc", "#{prefix}g++"}

      {:script, script_path, {module, args}} ->
        case {script_path, module} do
          {"", CCPrecompiler.UniversalBinary} ->
            {:script, module, args}

          _ ->
            Code.require_file(script_path)
            {:script, module, args}
        end

      {cc, cxx, cc_args, cxx_args} ->
        {EEx.eval_string(cc_args, cc: cc), EEx.eval_string(cxx_args, cxx: cxx)}
    end
  end

  @impl true
  def post_precompile_target(target) do
    config = Mix.Project.config()
    cc_precompiler_config = config[:cc_precompiler]
    cleanup(config, cc_precompiler_config[:cleanup], target)
  end

  defp cleanup(_, nil, _), do: :ok

  defp cleanup(config, make_target, current_precompilation_target) when is_binary(make_target) do
    exec =
      System.get_env("MAKE") ||
        os_specific_executable(Keyword.get(config, :make_executable, :default))

    makefile = Keyword.get(config, :make_makefile, :default)
    env = Keyword.get(config, :make_env, %{})
    env = if is_function(env), do: env.(), else: env
    env = default_env(config, env, current_precompilation_target)

    # In OTP 19, Erlang's `open_port/2` ignores the current working
    # directory when expanding relative paths. This means that `:make_cwd`
    # must be an absolute path. This is a different behaviour from earlier
    # OTP versions and appears to be a bug. It is being tracked at
    # https://bugs.erlang.org/browse/ERL-175.
    cwd = Keyword.get(config, :make_cwd, ".") |> Path.expand(File.cwd!())

    if String.contains?(cwd, " ") do
      IO.warn(
        "the absolute path to the makefile for this project contains spaces. Make might " <>
          "not work properly if spaces are present in the path. The absolute path is: " <>
          inspect(cwd)
      )
    end

    base = exec |> Path.basename() |> Path.rootname()
    args = args_for_makefile(base, makefile) ++ [make_target]

    case cmd(exec, args, cwd, env) do
      0 ->
        :ok

      exit_status ->
        raise_cleanup_error(exec, exit_status)
    end
  end

  defp raise_cleanup_error(exec, exit_status) do
    Mix.raise(~s{Could not complete cleanup work with "#{exec}" (exit status: #{exit_status}).\n})
  end

  # Returns a map of default environment variables
  # Defaults may be overwritten.
  defp default_env(config, default_env, current_precompilation_target) do
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
        "EMU" => nil,

        # cc_precompiler
        "CC_PRECOMPILER_CURRENT_TARGET" => current_precompilation_target
      },
      default_env
    )
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

      {:unix, type} when type in [:freebsd, :openbsd, :netbsd] ->
        "gmake"

      _ ->
        "make"
    end
  end

  # Returns a list of command-line args to pass to make (or nmake/gmake) in
  # order to specify the makefile to use.
  defp args_for_makefile("nmake", :default), do: ["/F", "Makefile.win"]
  defp args_for_makefile("nmake", makefile), do: ["/F", makefile]
  defp args_for_makefile(_, :default), do: []
  defp args_for_makefile(_, makefile), do: ["-f", makefile]

  # Runs `exec [args]` in `cwd` and prints the stdout and stderr in real time,
  # as soon as `exec` prints them (using `IO.Stream`).
  defp cmd(exec, args, cwd, env) do
    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true,
      cd: cwd,
      env: env
    ]

    {%IO.Stream{}, status} = System.cmd(find_executable(exec), args, opts)
    status
  end

  defp find_executable(exec) do
    System.find_executable(exec) ||
      Mix.raise("""
      "#{exec}" not found in the path. If you have set the MAKE environment variable,
      please make sure it is correct.
      """)
  end

  defp env(var, default) do
    System.get_env(var) || default
  end
end
