# Telemetry.Metrics

[![CI](https://github.com/beam-telemetry/telemetry_metrics/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-telemetry/telemetry_metrics/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)

Telemetry.Metrics provides a common interface for defining metrics based on
[`:telemetry`](https://github.com/beam-telemetry/telemetry) events. These metrics
can then be published to different backends using our Reporters API. See the
[official documentation](https://hexdocs.pm/telemetry_metrics) for more information.

## Reporters

The following reporters are available:

  * [peep](https://github.com/rkallos/peep) - reporter for Prometheus and StatsD

  * [telemetry_metrics_statsd](https://github.com/beam-telemetry/telemetry_metrics_statsd) - reporter for StatsD

  * [telemetry_metrics_prometheus](https://github.com/beam-telemetry/telemetry_metrics_prometheus) - reporter for Prometheus

Other libraries are also available to report telemetry events, albeit without using Telemetry.Metrics, such as [OpenTelemetry bindings for telemetry](https://github.com/open-telemetry/opentelemetry-erlang-contrib/tree/main/utilities/opentelemetry_telemetry).

## Copyright and License

Telemetry.Metrics is copyright (c) 2019 Erlang Ecosystem Foundation and Erlang Solutions.

Telemetry.Metrics source code is released under Apache License, Version 2.0.

See [LICENSE](LICENSE) and [NOTICE](NOTICE) files for more information.
