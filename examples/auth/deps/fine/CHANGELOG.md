# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v0.1.4](https://github.com/elixir-nx/fine/tree/v0.1.4) (2025-08-14)

### Added

- Expanded encoders and decoders for STL containers to support custom allocators ([#5](https://github.com/elixir-nx/fine/pull/5))
- Comparison operations for `fine::Term` to enable use with `std::map` ([#10](https://github.com/elixir-nx/fine/pull/10))
- Implicit item type conversion for `fine::Ok` and `fine::Error` ([#13](https://github.com/elixir-nx/fine/pull/13))
- Implemented `std::hash` for `fine::Term` and `fine::Atom` to enable use with `std::unordered_map` ([#11](https://github.com/elixir-nx/fine/pull/11))

## [v0.1.3](https://github.com/elixir-nx/fine/tree/v0.1.3) (2025-07-31)

### Fixed

- Include files being copied into releases

## [v0.1.2](https://github.com/elixir-nx/fine/tree/v0.1.2) (2025-07-29)

### Added

- Added default constructor to `fine::Term`
- Improved error message when trying to decode a remote PID

## [v0.1.1](https://github.com/elixir-nx/fine/tree/v0.1.1) (2025-06-27)

### Added

- Encoding and decoding for `std::string_view` as a better alternative to `ErlNifBinary` ([#4](https://github.com/elixir-nx/fine/pull/4))
- `fine::make_new_binary` to streamline returning large buffers ([#6](https://github.com/elixir-nx/fine/pull/6))
- Erlang-backed synchronization primitives in `fine/sync.hpp` ([#7](https://github.com/elixir-nx/fine/pull/7))

## [v0.1.0](https://github.com/elixir-nx/fine/tree/v0.1.0) (2025-02-19)

Initial release.
