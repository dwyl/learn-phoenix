# Changelog

## v2.8.1 (2025-06-24)

* Enhancement
  * Automatically set and read process labels in error reports

## v2.8.0 (2025-06-24)

* Enhancement
  * Allow `unallow_existing` as an opt to `ownership_allow/4`
  * Improve ETS performance by enabling descentralized counters
  * Increase default queue interval to 2000ms

## v2.7.0 (2024-07-02)

* Enhancements
  * Add API for retrieving pool metrics
  * Include a built-in listener that emits telemetry events

* Bug fixes
  * Discard EXIT messages from trapped exits

## v2.6.0 (2023-10-15)

* Enhancements
  * Call `disconnect` on terminate
  * Allow `handle_begin` callbacks to return query for logging purposes
  * Add `:connection_listeners_tag`
  * Add `DBConnection.available_connection_options/0`
  * Add `DBConnection.available_start_options/0`

## v2.5.0 (2023-04-10)

* Internal changes
  * No longer depend on `connection`

## v2.4.3 (2022-11-22)

* Bug fixes
  * Fix bug where `disconnect_all/2` interval would be disabled above 4294ms
  * Add `:idle_limit` to limit the amount of disconnections on a ping

## v2.4.2 (2022-03-03)

* Enhancements
  * Add `DBConnection.connection_module/1`

## v2.4.1 (2021-10-14)

* Enhancements
  * Add `DBConnection.disconnect_all/2`

## v2.4.0 (2021-04-02)

* Enhancements
  * Add telemetry events for connection errors
  * Use `:rand` default algorithm
  * Allow decentralized lookups on DBConnection.Ownership

## v2.3.1 (2020-11-25)

* Enhancements
  * Add `:connection_listeners` to `DBConnection.start_link/2`
  * Allow connection `~> 1.0`

## v2.3.0 (2020-10-14)

This release requires Elixir v1.7+.

* Bug fixes
  * Fix deprecation warnings related to the use of `System.stacktrace()`

## v2.2.2 (2020-04-22)

* Bug fixes
  * Make sure all idle connections in the pool are pinged on each idle interval

## v2.2.1 (2020-02-04)

* Enhancements
  * Remove warnings

## v2.2.0 (2019-12-11)

* Enhancements
  * Add `:idle_time` to `DBConnection.LogEntry`
  * Ping all stale connections on idle interval
  * Add `crash_reason` to relevant Logger error reports
  * Ping all stale connections on idle interval. One possible downside of this approach is that we may shut down all connections at once and if there is a request around this time, the response time will be higher. However, this is likely better than the current approach, where we ping only the first one, which means we can have a pool of stale connections. The current behaviour is the same as in v1.0

## v2.1.1 (2019-07-17)

* Enhancements
  * Reduce severity in client exits to info
  * Improve error message on redirect checkout

* Bug fixes
  * Make sure ownership timeout is respected on automatic checkouts

## v2.1.0 (2019-06-07)

* Enhancements
  * Require Elixir v1.6+
  * Include client stacktrace on check out timeouts
