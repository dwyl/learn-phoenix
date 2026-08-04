# CC Precompiler

[![Hex.pm](https://img.shields.io/hexpm/v/cc_precompiler.svg?style=flat&color=blue)](https://hex.pm/packages/cc_precompiler)

C/C++ Cross-compiler Precompiler is a library that supports [elixir_make](https://github.com/elixir-lang/elixir_make)'s precompilation feature. It's customisble and easy to extend.

The guide for how to `cc_precompiler` can be found in the `PRECOMPILATION_GUIED.md` file.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `cc_precompiler` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cc_precompiler, "~> 0.1.6"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/cc_precompiler>.

## Default Targets

By default, it will probe some well-known C/C++ crosss-compilers existing on your system:

#### Linux

  | Target Triplet          | Compiler Prefix, `prefix` | `CC`            | `CXX`           |
  |:------------------------|:--------------------------|:----------------|:----------------|
  | `x86_64-linux-gnu`      | `x86_64-linux-gnu-`       | `#{prefix}gcc` | `#{prefix}g++` |
  | `i686-linux-gnu`        | `i686-linux-gnu-`         | `#{prefix}gcc` | `#{prefix}g++` |
  | `aarch64-linux-gnu`     | `aarch64-linux-gnu-`      | `#{prefix}gcc` | `#{prefix}g++` |
  | `armv7l-linux-gnuabihf` | `arm-linux-gnueabihf-`    | `#{prefix}gcc` | `#{prefix}g++` |
  | `riscv64-linux-gnu`     | `riscv64-linux-gnu-`      | `#{prefix}gcc` | `#{prefix}g++` |
  | `powerpc64le-linux-gnu` | `powerpc64le-linux-gnu-`  | `#{prefix}gcc` | `#{prefix}g++` |
  | `s390x-linux-gnu`       | `s390x-linux-gnu-`        | `#{prefix}gcc` | `#{prefix}g++` |

  `cc_precompiler` will try to find `#{prefix}gcc` in `$PATH`, and if `#{prefix}gcc` can be found, then the correspondong target will be activiated. Otherwise, that target will be ignored.

#### macOS

  | Target Triplet          | Compiler Prefix, `prefix` | `CC`               | `CXX`              |
  |:------------------------|:--------------------------|:-------------------|:-------------------|
  | `x86_64-apple-darwin`   | N/A                       | `gcc -arch x86_64` | `g++ -arch x86_64` |
  | `aarch64-apple-darwin`  | N/A                       | `gcc -arch arm64`  | `g++ -arch arm64`  |

  `cc_precompiler` will try to find `gcc` in `$PATH`, and if `gcc` can be found, then both `x86_64` and `arm64` target will be activiated. Otherwise, both targets will be ignored.

#### Note
Triplet for current host will be always available, `:erlang.system_info(:system_architecture)`.

For macOS targets, the version part will be trimmed, e.g., `x86_64-apple-darwin21.6.0` will be `x86_64-apple-darwin`.

### Note
#### Conditionally switch on/off compilation flags depending on the target
During the compilation, `cc_precompiler` will set and update the environment variable `CC_PRECOMPILER_CURRENT_TARGET` to the current target's triplet.

The reason we might need this is that some 3rd party library may support some feature, like AVX, but they do not offer an auto-detection mechanism, and we have to manually switch on/off corresponding compilation flags.

An example with further explanation can be found on [cocoa-xu/nif_opt_flags](https://github.com/cocoa-xu/nif_opt_flags).

Last but not least, as the name suggests, this environment variable is set by `cc_precompiler`, thus if you switch to another precompiler, please check their manual for the equvilent.

### Customise Precompilation Targets

#### Quick Start

To add custom targets in addition to the default configuration, you can set `:include_default_ones` in `project.cc_precompiler.compilers`. 

Default (cross-)compiler will be included if it's `true`, otherwise only specified targets will be used.

Default value of `:include_default_ones` is `false` to avoid breaking changes.

If a custom target has the same name as a default one, then the custom one will override the default configuration for that target (e.g., the `x86_64-linux-gnu` entry below will override the default gcc configuration and use clang instead).

```elixir
def project do
  [
    # ...
    cc_precompiler: [
      compilers: %{
        {:unix, :linux} => %{
          :include_default_ones => true,
          "my-custom-target" => {
            "my-custom-target-gcc",
            "my-custom-target-g++"
          },
          "x86_64-linux-gnu" => {
            "x86_64-linux-gnu-clang",
            "x86_64-linux-gnu-clang++"
          }
        }
      }
    ]
  ]
end
```

#### Fully Customise Precompilation Targets

```elixir

def project do
[ 
  # ...
  cc_precompiler: [
    # optional config key
    #   false - target triplet for the current machine will be included in all available targets
    #   true  - only targets listed in `compilers` will be included in all available targets
    # defaults to `false`
    only_listed_targets: true,

    # optional config key
    #   this option is valid if and only if `only_listed_targets` is set to `true`
    #   - when `exclude_current_target` is `true`, it excludes current target (i.e., the machine that builds these binaries)
    #     from the list. This can be helpful when you're doing some complex cross-compilations, 
    #     e.g., you'd like to specify which CI job should build for the x86_64-linux-gnu target
    #     this will force current target to be excluded from the list
    exclude_current_target: false,

    # optional config key
    # clean up the priv directory between different targets
    # 
    # for example, common assets for different targets can stay
    # in the `priv` directory (instead of copying/downloading them
    # multiple times)
    # but target specific assets or .o files should be cleaned
    # so that `make` can compile/generate these files for the next target
    #
    # the value for `cleanup` should be a string indicating the cleanup target
    # in the makefile.
    # 
    # for example, cc_precompiler will call `make mycleanup` between each build
    # if the value for the key `cleanup` is set to `mycleanup`
    #
    # also, cc_precompiler will stop if `make mycleanup` exited with non-zero code
    #
    # the default value for this key is `nil`, and in such case, cc_precompiler 
    # will not do anything between each build
    cleanup: "mycleanup",

    # optional config key
    #   true - the corresponding target will be available as long as we can detect either `CC` or `CXX`
    #   false  - both `CC` and `CXX` should be present on the system
    # defaults to `false`
    allow_missing_compiler: false,

    # optional config that provides a map of available compilers
    # on different systems
    compilers: %{
      # key (`:os.type()`)
      #   this allows us to provide different available targets 
      #   on different systems
      # value is a map that describes which compilers are available
      #
      # key == {:unix, :linux} => when compiling on Linux
      {:unix, :linux} => %{
        # key (target triplet) => `riscv64-linux-gnu`
        # value => `PREFIX`
        #   - for strings, the string will be used as the prefix of
        #         the C and C++ compiler respectively, i.e.,
        #         CC=`#{prefix}gcc`
        #         CXX=`#{prefix}g++`
        "riscv64-linux-gnu" => "riscv64-linux-gnu-",
        # key (target triplet) => `armv7l-linux-gnueabihf`
        # value => `{CC, CXX}`
        #   - for 2-tuples, the elements are the executable name of
        #         the C and C++ compiler respectively
        "armv7l-linux-gnueabihf" => {
          "arm-linux-gnueabihf-gcc",
          "arm-linux-gnueabihf-g++"
        },
        # key (target triplet) => `armv7l-linux-gnueabihf`
        # value => `{CC_EXECUTABLE, CXX_EXECUTABLE, CC_TEMPLATE, CXX_TEMPLATE}`
        #
        # - for 4-tuples, the first two elements are the same as in
        #       2-tuple, the third and fourth elements are the template
        #       string for CC and CPP/CXX. for example,
        #       
        #       the last entry below shows the example of using zig as the
        #       crosscompiler for `aarch64-linux-musl`, 
        #       the "CC" will be
        #           "zig cc -target aarch64-linux-musl", 
        #       and "CXX" and "CPP" will be
        #           "zig c++ -target aarch64-linux-musl"
        "aarch64-linux-musl" => {
          "zig", 
          "zig", 
          "<% cc %> cc -target aarch64-linux-musl", 
          "<% cxx %> c++ -target aarch64-linux-musl"
        }
      },
      # key == {:unix, :darwin} => when compiling on macOS
      {:unix, :darwin} => %{
        # key (target triplet) => `aarch64-apple-darwin`
        # value => `{CC, CXX}`
        "aarch64-apple-darwin" => {
          "gcc -arch arm64", "g++ -arch arm64"
        },
        # key (target triplet) => `aarch64-linux-musl`
        # value => `{CC_EXECUTABLE, CXX_EXECUTABLE, CC_TEMPLATE, CXX_TEMPLATE}`
        "aarch64-linux-musl" => {
          "zig",
          "zig",
          "<% cc %> cc -target aarch64-linux-musl",
          "<% cxx %> c++ -target aarch64-linux-musl"
        },
        # key (target triplet) => `my-custom-target`
        # - for 3-tuples, the first element should be `:script`
        #       the second element is the path to the elixir script file
        #       the third element is a 2-tuple, 
        #          the first one is the name of the module
        #          the second one is custom args
        #       the module need to impl the `compile/5` callback declared in 
        #          `CCPrecompiler.CompilationScript`
        "my-custom-target" => {
          :script, "custom.exs", {CustomCompile, []}
        },
        # key (target triplet) => `macos-universal`
        # on macOS, CCPrecompiler also provides a builtin module to create 
        # universal binary for NIF libraries that only has a `nif.so` file
        "macos-universal" => {
          :script, "", {CCPrecompiler.UniversalBinary, []}
        }
      }
    }
  ]
]
```

`CCPrecompiler.CompilationScript` is defined as follows,

```elixir
defmodule CCPrecompiler.CompilationScript do
  @callback compile(
              app :: atom(),
              version :: String.t(),
              nif_version :: String.t(),
              target :: String.t(),
              command_line_args :: [String.t()],
              custom_args :: [String.t()]
            ) :: :ok | {:error, String.t()}
end
```

### Custom Compilation Script Examples
#### Compile with `ccache`

```elixir
defmodule CCPrecompiler.CCache do
  @moduledoc """
  Compile with ccache

  ## Example

    "x86_64-linux-gnu" => {
      :script, "custom.exs", {CCPrecompiler.CCache, []}
    }

  It's also possible to do this using a 4-tuple:

    "x86_64-linux-musl" => {
      "gcc", "g++", "ccache <% cc %>", "ccache <% cxx %>"
    }

  """

  @behaviour CCPrecompiler.CompilationScript

  @impl CCPrecompiler.CompilationScript
  def compile(app, version, nif_version, target, args, _custom_args) do
    System.put_env("CC", "ccache gcc")
    System.put_env("CXX", "ccache g++")
    System.put_env("CPP", "ccache g++")

    ElixirMake.Precompiler.mix_compile(args)
  end
end
```

#### Build A Universal NIF Binary on macOS
File can be found at `lib/complation_script/universal_binary.ex`.

```elixir
defmodule CCPrecompiler.UniversalBinary do
  @moduledoc """
  Build a universal binary on macOS

  ## Example

    "macos-universal" => {
      :script, "universal_binary.exs", {CCPrecompiler.UniversalBinary, []}
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

    {%IO.Stream{}, exit_status} = System.cmd("lipo", ["-create", "-output", compiled_bin, x86_64_bin, aarch64_bin])

    File.rm!(x86_64_bin)
    File.rm!(aarch64_bin)

    if exit_status == 0 do
      :ok
    else
      Mix.raise("Failed to create universal binary")
    end
  end
end
```
