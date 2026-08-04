# Precompilation guide

This guide has two sections, the first one is intended for precompiler module developers. It covers a minimal example of creating a precompiler module. The second section is intended for library developers who want their library to be able to use precompiled artefacts in a simple way.

## Library Developer

This guide assumes you have already added `elixir_make` to your library and you have written a `Makefile` that compiles the native code in your project. Once your native code compile and works as expected, you are now ready to precompile it.

A full demo project is available on [cocoa-xu/cc_precompiler_example](https://github.com/cocoa-xu/cc_precompiler_example).

### Setup mix.exs

To use a precompiler module such as the `CCPrecompiler` example above, we first add the precompiler (`:cc_precompiler` here) and `:elixir_make` to `deps`.

```elixir
def deps do
[
    # ...
    {:elixir_make, "~> 0.6", runtime: false},
    {:cc_precompiler, "~> 0.1", runtime: false, github: "cocoa-xu/cc_precompiler"}
    # ...
]
end
```

Then add `:elixir_make` to the `compilers` list, and set `CCPrecompile` as the value for `make_precompiler`.

```elixir
@version "0.1.0"
def project do
  [
    # ...
    compilers: [:elixir_make] ++ Mix.compilers(),
    # elixir_make specific config
    make_precompiler: {:nif, CCPrecompiler},
    make_precompiler_url: "https://github.com/cocoa-xu/cc_precompiler_example/releases/download/v#{@version}/@{artefact_filename}",
    make_precompiler_filename: "nif",
    make_precompiler_priv_paths: ["nif.*"],
    make_precompiler_unavailable_target: :compile,
    # ...
  ]
end
```

Another required field is `make_precompiled_url`. It is a URL template to the artefact file.

`@{artefact_filename}` in the URL template string will be replaced by corresponding artefact filenames when fetching them. For example, `cc_precompiler_example-nif-2.16-x86_64-linux-gnu-0.1.0.tar.gz`.

Note that there is an optional config key for elixir_make, `make_precompiler_filename`. If the name (file extension does not count) of the shared library is different from your app's name, then `make_precompiler_filename` should be set. For example, if the app name is `"cc_precompiler_example"` while the name shared library is `"nif.so"` (or `"nif.dll"` on windows), then `make_precompiler_filename` should be set as `"nif"`.

Another optional config key is `make_precompiler_priv_paths`. For example, say the `priv` directory is organised as follows in Linux, macOS and Windows respectively,

Also, you can specify how to recover from unavailable targets using the `make_precompiler_unavailable_target` config key. Allowed values are `:compile` and `:ignore`. Defaults to `:compile`.

It is also possible to pass in a 2-arity function to `make_precompiler_unavailable_target`: the first argument is the triplet of the unavailable target, and the second argument is a list that contains all available targets given by the precompiler.

```
# Linux
.
├── assets
│   ├── model.onnx
│   └── data.json
├── lib
│   ├── libpriv1.so
│   ├── libpriv2.so
│   └── libpriv3.so
└── nif.so

# macOS
.
├── assets
│   ├── model.onnx
│   └── data.json
├── lib
│   ├── libpriv1.dylib
│   ├── libpriv2.dylib
│   └── libpriv3.dylib
└── nif.so

# Windows
.
├── assets
│   ├── model.onnx
│   └── data.json
├── lib
│   ├── libpriv1.dll
│   ├── libpriv2.dll
│   └── libpriv3.dll
└── nif.dll
```

By default, everything in `priv` will be included in the precompiled tar file. However, files in `assets` can be very large or platform-independent, therefore, we would like to only include the `nif.so` (`nif.dll`) file and everything in the `lib` directory in the precompiled tar file to reduce the footprint. In this case, we can set `make_precompiler_priv_paths` to `["nif.so", "nif.dll", "lib"]`.

Of course, wildcards (`?`, `**`, `*`) are supported when specifying files. For example, `["nif.*", "lib/*.so", "lib/*.dll", "lib/*.dylib"]` will include `nif.so` (Linux/macOS) or `nif.dll` (Windows), and `.so` or `.dll` files in the `lib` directory. 

Directory structures and symbolic links are preserved.

### (Optional) Test the NIF code locally

To test the NIF code locally, you can either set `force_build` to `true` or append `"-dev"` to your NIF library's version string.

```elixir
@version "0.1.0-dev"

def project do
  [
    # either append `"-dev"` to your NIF library's version string
    version: @version,
    # or set force_build to true
    force_build: true,
    # ...
  ]
end
```

Doing so will ask `elixir_make` to only compile for the current host instead of building for all available targets.

```shell
$ mix compile
cc -shared -std=c11 -O3 -fPIC -I"/usr/local/lib/erlang/erts-13.0.3/include" -undefined dynamic_lookup -flat_namespace -undefined suppress "/Users/cocoa/git/cc_precompiler_example/c_src/cc_precompiler_example.c" -o "/Users/cocoa/Git/cc_precompiler_example/_build/dev/lib/cc_precompiler_example/priv/nif.so"
$ mix test
make: Nothing to be done for `build'.
Generated cc_precompiler_example app
.

Finished in 0.00 seconds (0.00s async, 0.00s sync)
1 test, 0 failures

Randomized with seed 102464
```

### Precompile for available targets

It's possible to either setup a CI task to do the precompilation job or precompile on a local machine and upload the precompiled artefacts.

To precompile for all targets on a local machine:

```shell
MIX_ENV=prod mix elixir_make.precompile
```

Environment variable `ELIXIR_MAKE_CACHE_DIR` can be used to set the cache dir for the precompiled artefacts, for instance, to output precompiled artefacts in the cache directory of the current working directory, `export ELIXIR_MAKE_CACHE_DIR="$(pwd)/cache"`.

To setup a CI task such as GitHub Actions, the following workflow file can be used for reference:

```yml
name: precompile

on:
  push:
    tags:
      - 'v*'

jobs:
  linux:
    runs-on: ubuntu-latest
    env:
      MIX_ENV: "prod"
    steps:
      - uses: actions/checkout@v3

      - uses: erlef/setup-beam@v1
        with:
          otp-version: "25.1"
          elixir-version: "1.14"

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y build-essential automake autoconf pkg-config bc m4 unzip zip \
            gcc g++ \
            gcc-i686-linux-gnu g++-i686-linux-gnu \
            gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
            gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf \
            gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
            gcc-powerpc64le-linux-gnu g++-powerpc64le-linux-gnu \
            gcc-s390x-linux-gnu g++-s390x-linux-gnu

      - name: Get musl cross-compilers (Optional, use this if you have musl targets to compile)
        run: |
          for musl_arch in x86_64 aarch64 riscv64
          do
            wget "https://musl.cc/${musl_arch}-linux-musl-cross.tgz" -O "${musl_arch}-linux-musl-cross.tgz"
            tar -xf "${musl_arch}-linux-musl-cross.tgz"
          done

      - name: Mix Test
        run: |
          # Optional, use this if you have musl targets to compile
          for musl_arch in x86_64 aarch64 riscv64
          do
            export PATH="$(pwd)/${musl_arch}-linux-musl-cross/bin:${PATH}"
          done

          mix deps.get
          MIX_ENV=test mix test

      - name: Create precompiled library
        run: |
          export ELIXIR_MAKE_CACHE_DIR=$(pwd)/cache
          mkdir -p "${ELIXIR_MAKE_CACHE_DIR}"
          mix elixir_make.precompile

      - uses: softprops/action-gh-release@v1
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: |
            cache/*.tar.gz

  macos:
    runs-on: macos-11
    env:
      MIX_ENV: "prod"

    steps:
      - uses: actions/checkout@v3

      - name: Install erlang and elixir
        run: |
          brew install erlang elixir
          mix local.hex --force
          mix local.rebar --force

      - name: Mix Test
        run: |
          mix deps.get
          MIX_ENV=test mix test

      - name: Create precompiled library
        run: |
          export ELIXIR_MAKE_CACHE_DIR=$(pwd)/cache
          mkdir -p "${ELIXIR_MAKE_CACHE_DIR}"
          mix elixir_make.precompile

      - uses: softprops/action-gh-release@v1
        if: startsWith(github.ref, 'refs/tags/')
        with:
          files: |
            cache/*.tar.gz
```

### Generate checksum file
After CI has finished, you can fetch the precompiled binaries from GitHub.

```shell
$ MIX_ENV=prod mix elixir_make.checksum --all --ignore-unavailable
```

Meanwhile, a checksum file will be generated. In this example, the checksum file will be named as `checksum.exs` in current working directory.

This checksum file is extremely important in the scenario where you need to release a Hex package using precompiled NIFs. It's **MANDATORY** to include this file in your Hex package (by updating the `files` field in the `mix.exs`). Otherwise your package **won't work**.

```elixir
defp package do
  [
    files: [
      # ...
      "checksum.exs",
      # ...
    ],
    # ...
  ]
end
```

However, there is no need to track the checksum file in your version control system (git or other).

### (Optional) Test fetched artefacts can work locally
```shell
# delete previously built binaries so that
# elixir_make will try to restore the NIF library
# from the downloaded tarball file
$ rm -rf _build/prod/lib/cc_precompiler_example
# set to prod env and test everything
$ MIX_ENV=prod mix test
==> castore
Compiling 1 file (.ex)
Generated castore app
==> elixir_make
Compiling 5 files (.ex)
Generated elixir_make app
==> cc_precompiler
Compiling 1 file (.ex)
Generated cc_precompiler app

20:47:42.262 [debug] Restore NIF for current node from: /Users/cocoa/Library/Caches/cc_precompiler_example-nif-2.16-aarch64-apple-darwin-0.1.0.tar.gz
==> cc_precompiler_example
Compiling 1 file (.ex)
Generated cc_precompiler_example app
.

Finished in 0.01 seconds (0.00s async, 0.01s sync)
1 test, 0 failures

Randomized with seed 539590
```

## Recommended flow
To recap, the suggested flow is the following:

1. Choose an appropriate precompiler for your NIF library and set all necessary options in the `mix.exs`.
2. (Optional) Test if your NIF library compiles locally.

  ```shell
  mix compile
  mix test
  ```

3. (Optional) Test if your NIF library can precompile to all specified targets locally.
  ```shell
  MIX_ENV=prod mix elixir_make.precompile
  ```

4. Precompile your library on CI or locally.

  ```shell
  # locally
  MIX_ENV=prod mix elixir_make.precompile
  # CI
  # please see the docs above
  ```

5. Fetch precompiled binaries from GitHub.

  ```shell
  # only fetch artefact for current host
  MIX_ENV=prod mix elixir_make.checksum --only-local --print
  # fetch all
  MIX_ENV=prod mix elixir_make.checksum --all --print
  # to fetch all available artefacts at the moment
  MIX_ENV=prod mix elixir_make.checksum --all --print --ignore-unavailable
  ```

6. (Optional) Test if the downloaded artefacts works as expected.

  ```shell
  rm -rf _build/prod/lib/NIF_LIBRARY_NAME
  MIX_ENV=prod mix test
  ```

6. Update Hex package to include the checksum file.
7. Release the package to Hex.pm (make sure your release includes the correct files).
