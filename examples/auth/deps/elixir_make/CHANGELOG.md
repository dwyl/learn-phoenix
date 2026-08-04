# Changelog

## v0.9.0 (2024-11-12)

  * Rely on certificate stores provided by Erlang/OTP 25+
  * Support setting `:force_build` opts in config:

    ```elixir
    config :elixir_make, :force_build, app1: true, app2: false
    ```

## v0.8.4 (2024-06-04)

  * Support configuring `make_precompiler_downloader`
  * Support DragonFlyBSD
  * Support non-UTF8 encoding from compilation (may happen on Windows)

## v0.8.3 (2024-03-24)

  * Support storing checksum of individial precompilation artefacts

## v0.8.2 (2024-03-10)

  * Fix checksum error when checksuming NIF version

## v0.8.1 (2024-03-10)

  * Fix checksum error when falling back to a previous NIF version

## v0.8.0 (2024-03-10)

  * Fallback to the previous compatible NIF version by default
  * Deprecate availability in favor of passing a function to `:versions`

## v0.7.8 (2024-01-17)

  * List certifi as an optional dependency

## v0.7.7 (2023-06-01)

  * Fix compiler in umbrella apps

## v0.7.6 (2023-03-17)

  * Do not display error message when a target is unavailable
  * Allow usage of castore 1.0

## v0.7.5 (2023-02-18)

  * Support precompiling for multiple NIF versions

## v0.7.4 (2023-02-17)

  * Preload Erlang/OTP applications for Elixir v1.15+

## v0.7.3 (2022-12-27)

  * Add `post_precompile_target` to `ElixirMake.Precompiler` behaviour

## v0.7.2 (2022-12-14)

  * Allow precompiler to configure behaviour for unavailable targets

## v0.7.1 (2022-12-07)

  * Use CACerts from Erlang/OTP 25 if available

## v0.7.0 (2022-12-02)

  * Support precompilation with custom precompilers
  * Don't pass default Erlang environment variables into make

## v0.6.3 (2021-10-19)

  * Fallback to `make` if `nmake` is not available on Windows.

## v0.6.2 (2020-12-03)

  * Fix permissions for some files in the repository.

## v0.6.1 (2020-09-07)

  * Warn on paths that contain spaces.
  * Use `gmake` on NetBSD.

## v0.6.0 (2019-06-10)

  * Start tracking CHANGELOG.
