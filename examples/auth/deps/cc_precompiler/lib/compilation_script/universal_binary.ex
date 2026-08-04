defmodule CCPrecompiler.UniversalBinary do
  @moduledoc """
  Build a universal binary on macOS

  ## Example

    "macos-universal" => {
      :script, "", {CCPrecompiler.UniversalBinary, []}
    }

  """

  @behaviour CCPrecompiler.CompilationScript

  @impl CCPrecompiler.CompilationScript
  def compile(_app, _version, _nif_version, _target, args, _custom_args) do
    config = Mix.Project.config()
    app_priv = Path.join(Mix.Project.app_path(config), "priv")
    make_precompiler_filename = config[:make_precompiler_filename] || "nif"
    nif_file = "#{make_precompiler_filename}.so"

    compiled_bin = Path.join(app_priv, nif_file)
    x86_64_bin = Path.join(app_priv, "#{make_precompiler_filename}_x86_64.so")
    aarch64_bin = Path.join(app_priv, "#{make_precompiler_filename}_aarch64.so")

    File.rm(compiled_bin)

    # first we compile `x86_64-apple-darwin`
    :ok = System.put_env("CC", "gcc -arch x86_64")
    System.put_env("CXX", "gcc -arch x86_64")
    System.put_env("CPP", "g++ -arch x86_64")
    ElixirMake.Compiler.compile(args)
    File.rename!(compiled_bin, x86_64_bin)

    # then we compile `aarch64-apple-darwin`
    System.put_env("CC", "gcc -arch arm64")
    System.put_env("CXX", "gcc -arch arm64")
    System.put_env("CPP", "g++ -arch arm64")
    ElixirMake.Compiler.compile(args)
    File.rename!(compiled_bin, aarch64_bin)

    {_, exit_status} =
      System.cmd("lipo", ["-create", "-output", compiled_bin, x86_64_bin, aarch64_bin])

    File.rm!(x86_64_bin)
    File.rm!(aarch64_bin)

    if exit_status == 0 do
      :ok
    else
      Mix.raise("Failed to create universal binary")
    end
  end
end
