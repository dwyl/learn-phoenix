# Changelog

## v0.1.11 (2025-08-02)

- allow `{:elixir_make, "~> 0.7 or ~> 0.8 or ~> 0.9"}` 

## v0.1.10 (2024-03-10)

- allow `{:elixir_make, "~> 0.7 or ~> 0.8"}` 

## v0.1.9 (2023-11-16)

- added an `exclude_current_target` option
- updated ex_doc

## v0.1.8 (2023-07-19)

### Changed

Fixed `CCPrecompiler.all_supported_targets(:fetch)`. It should fetch and merge default available compilers when `include_default_ones` is `true`.

## v0.1.7 (2022-03-13)

### Added
- using `:include_default_ones` in `project.cc_precompiler.compilers`. Default (cross-)compiler will be included if it's `true`, otherwise only specified targets will be used.

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

## v0.1.6 (2022-02-20)

### Added
- allow missing CC or CXX when detecting available targets by setting `allow_missing_compiler` to `true`.

  Adding this option because there is no need to require the presence of both CC and CXX for projects that only uses one of them.

  ```elixir
  def project do
    [ 
    # ...
    cc_precompiler: [
        # optional config key
        #   true - the corresponding target will be available as long as we can detect either `CC` or `CXX`
        #   false  - both `CC` and `CXX` should be present on the system
        # defaults to `false`
        allow_missing_compiler: false,
        # ...
    ],
    # ...
    ]
  end
  ```
