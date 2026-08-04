# Changelog

## v1.1.0 (2024-03-25)

* Add `handle_cancelled/2` pool callback

## v1.0.0 (2023-03-21)

Stable release.

## v0.2.6 (2022-02-18)

* Fix a bug on idle timeout causing the pool to empty

## v0.2.5 (2022-02-12)

* Add `handle_ping` to manage idle resources
* Only compute `monotonic_time` if `worker_idle_timeout` is provided

## v0.2.4 (2021-02-16)

* Fix a bug with lazy pool starting more connections than specified

## v0.2.3 (2020-10-24)

* Support `lazy: true` instead of `strategy: :lifo` (v0.2.2 has been retired)

## v0.2.2 (2020-10-23)

* Support `strategy: :lifo` for queue handling

## v0.2.1 (2020-09-29)

* List `handle_update` as a callback

## v0.2.0 (2020-08-01)

* Rework all callbacks to receive the pool state
* Add `handle_enqueue`, `handle_dequeue`, and `handle_update`
