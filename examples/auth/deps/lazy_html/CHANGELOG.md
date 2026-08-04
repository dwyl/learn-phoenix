# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [v0.1.7](https://github.com/dashbitco/lazy_html/tree/v0.1.7) (2025-08-29)

### Updated

- Updated Lexbor version ([#21](https://github.com/dashbitco/lazy_html/pull/21))

## [v0.1.6](https://github.com/dashbitco/lazy_html/tree/v0.1.6) (2025-08-07)

### Fixed

- Fixed regression in `LazyHTML.Tree.to_html/1` memory usage ([#19](https://github.com/dashbitco/lazy_html/pull/19))

## [v0.1.5](https://github.com/dashbitco/lazy_html/tree/v0.1.5) (2025-08-05)

### Added

- Added `LazyHTML.Tree.postreduce/3` and `LazyHTML.Tree.prereduce/3` ([#15](https://github.com/dashbitco/lazy_html/pull/15))

### Changed

- Lowered the runtime glibc version requirement ([#16](https://github.com/dashbitco/lazy_html/pull/16))

## [v0.1.4](https://github.com/dashbitco/lazy_html/tree/v0.1.4) (2025-08-04)

### Added

- Added `LazyHTML.html_escape/1` ([#14](https://github.com/dashbitco/lazy_html/pull/14))

## [v0.1.3](https://github.com/dashbitco/lazy_html/tree/v0.1.3) (2025-06-26)

### Added

- Added `:skip_whitespace_nodes` option to `LazyHTML.to_tree/2` ([#10](https://github.com/dashbitco/lazy_html/pull/10))

## [v0.1.2](https://github.com/dashbitco/lazy_html/tree/v0.1.2) (2025-06-23)

### Fixed

- `LazyHTML.from_tree/1` to preserve attribute name casing inside `<svg>` ([#9](https://github.com/dashbitco/lazy_html/pull/9))

## [v0.1.1](https://github.com/dashbitco/lazy_html/tree/v0.1.1) (2025-05-24)

### Fixed

- Fix `<template>` children being ignored in `LazyHTML.to_html/1`, `LazyHTML.to_tree/1`, `LazyHTML.from_tree/1` ([#5](https://github.com/dashbitco/lazy_html/pull/5))

## [v0.1.0](https://github.com/dashbitco/lazy_html/tree/v0.1.0) (2025-04-04)

Initial release.
