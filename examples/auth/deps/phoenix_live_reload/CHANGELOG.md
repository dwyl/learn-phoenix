# Changelog

## 1.6.1 (2025-08-31)

* Enhancements
  * Set `:phoenix_live_reload` private field to downstream instrumentation
  * Add `@import` directive support to CSS reload strategy

## 1.6.0 (2025-04-10)

* Enhancements
  * Add support for `__RELATIVEFILE__` when invoking editors
  * Change the default target window to `:parent` to not reload the whole page if a Phoenix app is shown inside an iframe. You can get the old behavior back by setting the `:target_window` option to `:top`:
    ```elixir
    config :phoenix_live_reload, MyAppWeb.Endpoint,
      target_window: :top,
      ...
    ```

* Bug fixes
  * Inject iframe if web console logger is enabled but there are no patterns
  * Allow web console to shutdown cleanly

## 1.5.3 (2024-03-27)

* Bug fixes
  * Fix warnings on earlier Elixir versions
  * Use darkcyan for log levels

## 1.5.2 (2024-03-11)

* Bug fixes
  * Fix CSS updates failing with errors
  * Fix logging errors caused by unknown server log types

## 1.5.1 (2024-02-29)

* Bug fixes
  * Fix regression on Elixir v1.14 and earlier

## 1.5.0 (2024-02-29)

* Improvements
  * Introduce streaming server logs to the browser's web console with the new `:web_console_logger` endpoint configuration
  * Introduce `openEditorAtCaller` and `openEditorAtDef` client functions for opening the developer's configured `PLUG_EDITOR` to the elixir source file/line given a DOM element
  * Dispatch `"phx:live_reload:attached"` to parent window when live reload is attached to server and awaiting changes

## 1.4.1 (2022-11-29)

* Improvements
  * Support new `:notify` configuration for third-party integration to file change events

## 1.4.0 (2022-10-29)

* Improvements
  * Allow reload events to be debounced instead of triggered immediately
  * Add option to trigger full page reloads on css changes
* Bug fixes
  * Handle false positives on `</body>` tags

## 1.3.3 (2021-07-06)

* Improvements
  * Do not attempt to fetch source map for phoenix.js

## 1.3.2 (2021-06-21)

* Improvements
  * Allow reload `:target_window` to be configured

## 1.3.1 (2021-04-12)

* Bug fixes
  * Use width=0 and height=0 on iframe

## 1.3.0 (2020-11-03)

This release requires Elixir v1.6+.

* Enhancements
  * Use `hidden` attribute instead of `style="display: none"`
  * Fix warnings on Elixir v1.11

* Deprecations
  * `:iframe_class` is deprecated in favor of `:iframe_attrs`

## 1.2.4 (2020-06-10)

* Bug fixes
  * Fix a bug related to improper live reload interval

## 1.2.3 (2020-06-10)

* Enhancements
  * Support the iframe_class option for live reload

## 1.2.2 (2020-05-13)

* Enhancements
  * Support the suffix option

## 1.2.1 (2019-05-24)

* Enhancements
  * Allow custom file_system backend options

## 1.2.0 (2018-11-07)

* Enhancements
  * Support Phoenix 1.4 transport changes

## 1.1.7 (2018-10-10)

* Enhancements
  * Relax version requirements to support Phoenix 1.4

## 1.1.6 (2018-09-28)

* Enhancements
  * Allow file system watcher backend to be configured
  * Add `:fs_poll` backend as fallback for generic OS support

## 1.1.5

* Bug fix
  * Use proper default interval of 100ms

## 1.1.4

* Enhancements
  * Support `:interval` configuration for cases where the live reloading was triggering too fast

* Bug fix
  * Support IE11
  * Fix CSS reloading in iframe

## 1.1.3 (2017-09-25)

* Bug fix
  * Do not return unsupported `:ignore` from live channel

## 1.1.2 (2017-09-25)

* Enhancements
  * Improve error messages

## 1.1.1 (2017-08-27)

* Enhancements
  * Bump `:file_system` requirement

* Bug fixes
  * Do not raise when response has no body

## 1.1.0 (2017-08-10)

* Enhancements
  * Use `:file_system` for file change notifications for improved reliability

## 1.0.8 (2017-02-01)

* Enhancements
  * Revert to `:fs` 0.9.1 to side-step rebar build problems

## 1.0.7 (2017-01-18)

* Enhancements
  * Update to latest `:fs` 2.12

## 1.0.6 (2016-11-29)

* Bug fixes
  * Remove warnings on Elixir v1.4
  * Do not try to access the endpoint if it is no longer loaded

## 1.0.5 (2016-05-04)

* Bug fixes
  * Do not include hard earmark requirement

## 1.0.4 (2016-04-29)

* Enhancements
  * Support Phoenix v1.2

## 1.0.3 (2016-01-11)

* Enhancements
  * Log whenever a live reload event is sent

## 1.0.2 (2016-01-07)

* Bug fixes
  * Fix issue where iframe path did not respect script_name

## 1.0.1 (2015-09-18)

* Bug fixes
  * Fix issue causing stylesheet link taps to duplicate on reload
