# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v1.1.0)

### Changed

Add support for measurements as second argument of keep/drop callback.

## [1.0.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v1.0.0)

No changes. API is considered stable.

## [0.6.2](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.6.2)

### Changed

Fix warnings and make some internal functions private.

## [0.6.1](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.6.1)

### Added

* Support latest telemetry

## [0.6.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.6.0)

This release brings an improvement that helps to track metrics based on event's metadata.
The `:measurement` option now accepts a two-arity function that takes both event measurements
and metadata, and returns a final measurement to be tracked by the metric.

Starting with this version Telemetry.Metrics requires minimum Elixir  1.7.0.

### Changed

* Extended the `:measurement` option to accept a function taking both event measurements
  and metadata.

## [0.5.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.5.0)

This release brings two new metric options, `:keep` and `:drop`, which allow users to specify
which telemetry events should be taken into account when collecting metrics. Reporters
supporting this version of `Telemetry.Metrics` need to respect these filtering rules.

In addition, the requirement to specify the distribution buckets has been dropped, since not
all reporters require configuration of buckets up front. Reporters which need the buckets to
be defined on the metric struct should accept it via `:reporter_options`.

### Added

* `:keep` and `:drop` options to filter events based on metadata

### Removed

* the `:buckets` option on the distribution metric

## [0.4.2](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.4.2)

### Fixed

* fixed a bug where unit conversion would fail if the measurement was missing

## [0.4.1](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.4.1)

### Fixed

* fixed a bug where unit conversion would fail if the measurement was `nil`

## [0.4.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.4.0)

### Added

* add `:reporter_options` option to all metric definitions for supplying reporter-specific
  configuration

### Changed

* `Telemetry.Metrics.t` type is now defined as a union of base metric definitions provided by
  the library

## [0.3.1](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.3.1)

### Added

* Add support for bytes, kilobytes and megabytes conversion

## [0.3.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.3.0)

### Added

* add `Telemetry.Metrics.ConsoleReporter` as an example reporter that prints data to the terminal
* add `summary/2` metric type
* add shortcut representation for `:buckets` in the `distribution/2` metric

## [0.2.1](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.2.1)

### Fixed

* dialyzer no longer fails on valid calls to `distribution/2` with `:buckets` option

## [0.2.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.2.0)

This release makes the library compatible with Telemetry v0.4.0. This means that metric values are
now based on one of the measurements. The first argument to all metric definition now specifies
the metric name, but also the source event name and the measurement - however, both of them can be
overridden using options.

### Added

* support for Telemetry v0.4.0 - the measurement can be configured indirectly via metric name or a
  `:measurement` option
* `:tag_values` option to apply final transformations to event metadata before it's used for tags
* `:event_name` and `:measurement` to override event name and measurement set via metric name
* ability to convert time unit of measurement via `:unit` option

### Changed

* first argument to all metric definitions is a metric name instead of event name
* `:unit` option now also accepts a tuple specifying the conversion of time unit of measurement

### Removed

* `:metadata` option - `:tag_values` can be used to transform event metadata now instead

## [0.1.0](https://github.com/beam-telemetry/telemetry_metrics/tree/v0.1.0)

### Added

* four metric specifications, `counter/2`, `sum/2`, `last_value/2` and `distribution/2`
