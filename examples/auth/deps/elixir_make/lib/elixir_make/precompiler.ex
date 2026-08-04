defmodule ElixirMake.Precompiler do
  @moduledoc """
  The behaviour for precompiler modules.
  """

  require Logger

  @typedoc """
  Target triplet.
  """
  @type target :: String.t()

  @doc """
  This callback should return a list of triplets ("arch-os-abi") for all supported targets
  of the given operation.

  For the `:compile` operation, `all_supported_targets` should return a list of targets that
  the current host is capable of (cross-)compiling to.

  For the `:fetch` operation, `all_supported_targets` should return the full list of targets.

  For example, GitHub Actions provides Linux, macOS and Windows CI hosts, when `operation` is
  `:compile`, the precompiler might return `["x86_64-linux-gnu"]` if it is running in the Linux
  CI environment, while returning `["x86_64-apple-darwin", "aarch64-apple-darwin"]` on macOS,
  or `["amd64-windows", "x86-windows"]` on Windows platform.

  When `operation` is `:fetch`, the precompiler should return the full list. The full list for
  the above example should be:

      [
        "x86_64-linux-gnu",
        "x86_64-apple-darwin",
        "aarch64-apple-darwin",
        "amd64-windows",
        "x86-windows"
      ]

  This allows the precompiler to do the compilation work in multilple hosts and gather all the
  artefacts later with `mix elixir_make.checksum --all`.
  """
  @callback all_supported_targets(operation :: :compile | :fetch) :: [target]

  @doc """
  This callback should return the target triplet for current node.
  """
  @callback current_target() :: {:ok, target} | {:error, String.t()}

  @doc """
  This callback will be invoked when the user executes the `mix compile`
  (or `mix compile.elixir_make`) command.

  The precompiler should then compile the NIF library "natively". Note that
  it is possible for the precompiler module to pick up other environment variables
  like `TARGET_ARCH=aarch64` and adjust compile arguments correspondingly.
  """
  @callback build_native(OptionParser.argv()) ::
              {Mix.Task.Compiler.status(), [Mix.Task.Compiler.Diagnostic.t()]}

  @doc """
  This callback should precompile the library to the given target(s).

  Returns `:ok` if the requested target has successfully compiled.
  """
  @callback precompile(OptionParser.argv(), target) :: :ok | {:error, String.t()}

  @doc """
  Optional post actions to run after each precompilation target is archived.

  It will be called when a target is precompiled and archived successfully.
  For example, actions can be deleting all target-specific files.
  """
  @callback post_precompile_target(target) :: :ok

  @doc """
  Optional post actions to run after all precompilation tasks are done.

  It will only be called at the end of the `mix elixir_make.precompile` command.
  For example, actions can be archiving all precompiled artefacts and uploading
  the archive file to an object storage server.
  """
  @callback post_precompile() :: :ok

  @doc """
  Optional recover actions when the current target is unavailable.

  There are two reasons that the current target might be unavailable:
  when the library only has precompiled binaries for some platforms,
  and it either

  - needs to be compiled on other platforms.

    The callback should return `:compile` for this case.

  - is intended to function as `noop` on other platforms.

    The callback should return `:ignore` for this case.

  Defaults to `:compile` if this callback is not implemented.
  """
  @callback unavailable_target(String.t()) :: :compile | :ignore

  @optional_callbacks post_precompile: 0, unavailable_target: 1, post_precompile_target: 1

  @doc """
  Invoke the regular Mix toolchain compilation.
  """
  def mix_compile(args) do
    ElixirMake.Compiler.compile(args)
  end
end
