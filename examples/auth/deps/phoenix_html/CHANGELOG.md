# Changelog

## 4.2.1 (2025-02-21)

* Enhancements
  * Add type to `Phoenix.HTML.FormField`
  * Allow keyword lists in options to use nil as key/value

## 4.2.0 (2024-12-28)

* Enhancements
  * Add `Phoenix.HTML.css_escape/1` to escape strings for use inside CSS selectors
  * Add the ability to pass `:hr` to `options_for_select/2` to render a horizontal rule

* Bug fixes
  * Pass form action through in FormData implementation

## v4.1.1 (2024-03-01)
  * Fix dependency resolution error

## v4.1.0 (2024-02-29)

* Enhancements
  * Introduce form `:action` and consider input as changed if action changes to support better change tracking

## v4.0.0 (2023-12-19)

This version removes deprecated functionality and moved all HTML helpers to a separate library. HTML Helpers are no longer used in new apps from Phoenix v1.7, instead it relies on function components from `Phoenix.LiveView`. Older applications who wish to maintain compatibility, add `{:phoenix_html_helpers, "~> 1.0"}` to your `mix.exs` and then replace `use Phoenix.HTML` in your applications by:

```elixir
import Phoenix.HTML
import Phoenix.HTML.Form
use PhoenixHTMLHelpers
```

## v3.3.3 (2023-10-09)

* Enhancements
  * Allow string fields on `input_changed?`

## v3.3.2 (2023-08-10)

* Enhancements
  * Address deprecations in Elixir v1.16+

* Deprecations
  * Deprecate `inputs_for/2` and `inputs_for/3` (without anonymous functions)

## v3.3.1 (2023-02-27)

* Bug fix
  * Set display to none on generated forms
  * Warn for maps with atom keys

## v3.3.0 (2023-02-10)

* Enhancements
  * Support deeply nested class lists
  * Implement Phoenix.HTML.Safe for URI
  * Implement Phoenix.HTML.FormData for Map

* Bug fix
  * Generate unique IDs for checkboxes based on the value
  * Use artificial button click instead of `form.submit` in JavaScript to trigger all relevant events
  * Fix a bug where nil/false/true attributes in `aria`/`data`/`phx` would emit empty or literal values, such as `"true"` and `"false"`. This release aligns them with all other attributes so both `nil` and `false` emit nothing. `true` emits the attribute with no value.

* Deprecations
  * `Phoenix.HTML.Tag.attributes_escape/1` is deprecated in favor of `Phoenix.HTML.attributes_escape/1`

## v3.2.0 (2021-12-18)

* Enhancements
  * Raise if the `id` attribute is set to a number. This is actually an invalid value according to the HTML spec and it can lead to problematic client behaviour, especially in LiveView and other client frameworks.
  * Allow `phx` attributes to be nested, similar to `aria` and `data` attributes
  * Allow hidden fields in forms to be a list of values

## v3.1.0 (2021-10-23)

* Bug fix
  * Do not submit data-method links if default has been prevented
* Deprecations
  * Deprecate `~E` and `Phoenix.HTML.Tag.attributes_escape/1`
  * Remove deprecated `Phoenix.HTML.Link.link/1`

## v3.0.4 (2021-09-23)

* Bug fix
  * Ensure `class={@class}` in HEEx templates and `:class` attribute in `content_tag` are properly escaped against XSS

## v3.0.3 (2021-09-04)

* Bug fix
  * Fix sorting of attributes in `tag`/`content_tag`

## v3.0.2 (2021-08-19)

* Enhancements
  * Support maps on `Phoenix.HTML.Tag.attributes_escape/1`

## v3.0.1 (2021-08-14)

* Enhancements
  * Add `Phoenix.HTML.Tag.csrf_input_tag/2`

## v3.0.0 (2021-08-06)

* Enhancements
  * Allow extra html attributes on the `:prompt` option in `select`
  * Make `Plug` an optional dependency
  * Prefix form id on inputs when it is given to `form_for/3`
  * Allow `%URI{}` to be passed to `link/2` and `button/2` as `:to`
  * Expose `Phoenix.HTML.Tag.csrf_token_value/1`
  * Add `Phoenix.HTML.Tag.attributes_escape/1`

* Bug fixes
  * Honor the `form` attribute when creating hidden checkbox input
  * Use `to_iso8601` as the standard implementation for safe dates and times

* Deprecations
  * `form_for` without an anonymous function has been deprecated. v3.0 has deprecated the usage, v3.1 will emit warnings, and v3.2 will fully remove the functionality

* Backwards incompatible changes
  * Strings given as attributes keys in `tag` and `content_tag` are now emitted as is (without being dasherized) and are also HTML escaped
  * Prefix form id on inputs when it is given to `form_for/3`
  * By default dates and times will format to the `to_iso8601` functions provided by their implementation
  * Do not include `csrf-param` and `method-param` in generated `csrf_meta_tag`
  * Remove deprecated `escape_javascript` in favor of `javascript_escape`
  * Remove deprecated `field_value` in favor of `input_value`
  * Remove deprecated `field_name` in favor of `input_name`
  * Remove deprecated `field_id` in favor of `input_id`

## v2.14.3 (2020-12-12)

* Bug fixes
  * Fix warnings on Elixir v1.12

## v2.14.2 (2020-04-30)

* Deprecations
  * Deprecate `Phoenix`-specific assigns `:view_module` and `:view_template`

## v2.14.1 (2020-03-20)

* Enhancements
  * Add `Phoenix.HTML.Form.options_for_select/2`
  * Add `Phoenix.HTML.Form.inputs_for/3`

* Bug fixes
  * Disable hidden input for disabled checkboxes

## v2.14.0 (2020-01-28)

* Enhancements
  * Remove enforce_utf8 workaround on forms as it is no longer required by browser
  * Remove support tuple-based date/time with microseconds calendar types
  * Allow strings as first element in `content_tag`
  * Add `:srcset` support to `img_tag`
  * Allow `inputs_for` to skip hidden fields

## v2.13.4 (2020-01-28)

* Bug fixes
  * Fix invalid :line in Elixir v1.10.0

## v2.13.3 (2019-05-31)

* Enhancements
  * Add atom support to FormData

* Bug fixes
  * Keep proper line numbers on .eex templates for proper coverage

## v2.13.2 (2019-03-29)

* Bug fixes
  * Stop event propagation when confirm dialog is canceled

## v2.13.1 (2019-01-05)

* Enhancements
  * Allow safe content to be given to label
  * Also escale template literals in `javascript_escape/1`

* Bug fixes
  * Fix deprecation warnings to point to the correct alternative

## v2.13.0 (2018-12-09)

* Enhancements
  * Require Elixir v1.5+ for more efficient template compilation/rendering
  * Add `Phoenix.HTML.Engine.encode_to_iodata!/1`
  * Add `Phoenix.HTML.Form.form_for/3` that works without an anonymous function

* Deprecations
  * Deprecate `Phoenix.HTML.escape_javascript/1` in favor of `Phoenix.HTML.javascript_escape/1` for consistency

## v2.12.0 (2018-08-06)

* Enhancements
  * Configurable and extendable data-confirm behaviour
  * Allow data-confirm with submit buttons
  * Support ISO 8601 formatted strings for date and time values

* Bug fixes
  * Provide a default id of the field name for `@conn` based forms

## v2.11.2 (2018-04-13)

* Enhancements
  * Support custom precision on time input

* Bug fixes
  * Do not raise when `:` is part of a path on link/button attributes

## v2.11.1 (2018-03-20)

* Enhancements
  * Add `label/1`
  * Copy the target attribute of the link in the generated JS form

* Bug fixes
  * Support any value that is html escapable in `radio_button`

## v2.11.0 (2018-03-09)

* Enhancements
  * Add date, datetime-local and time input types
  * Enable string keys to be usable with forms
  * Support carriage return in `text_to_html`
  * Add support for HTML5 boolean attributes to `content_tag` and `tag`
  * Improve performance by relying on `html_safe_to_iodata/1`
  * Protect against CSRF tokens leaking across hosts when the POST URL is dynamic
  * Require `to` attribute in links and buttons to explicitly pass protocols as a separate option for safety reasons

* Bug fixes
  * Guarantee `input_name/2` always returns strings
  * Improve handling of uncommon whitespace and null in `escape_javascript`
  * Escape value attribute so it is never treated as a boolean

* Backwards incompatible changes
  * The :csrf_token_generator configuration in the Phoenix.HTML app no longer works due to the improved security mechanisms

## v2.10.5 (2017-11-08)

* Enhancements
  * Do not require the :as option in form_for

## v2.10.4 (2017-08-15)

* Bug fixes
  * Fix formatting of days in datetime_builder

## v2.10.3 (2017-07-30)

* Enhancements
  * Allow specifying a custom CSRF token generator

* Bug fixes
  * Do not submit `method: :get` in buttons as "post"

## v2.10.2 (2017-07-24)

* Bug fixes
  * Traverse DOM elements up when handling data-method

## v2.10.1 (2017-07-22)

* Bug fixes
  * Only generate CSRF token if necessary

## v2.10.0 (2017-07-21)

* Enhancements
  * Support custom attributes in options in select

* Bug fixes
  * Accept non-binary values in textarea's content
  * Allow nested forms on the javascript side. This means `link` and `button` no longer generate a child form such as the `:form` option has no effect and "data-submit=parent" is no longer supported. Instead "data-to" and "data-method" are set on the entities and the form is generated on the javascript side of things

## v2.9.3 (2016-12-24)

* Bug fixes
  * Once again support any name for atom forms

## v2.9.2 (2016-12-24)

* Bug fixes
  * Always read from `form.params` and then from `:selected` in `select` and `multiple_select` before falling back to `input_value/2`

## v2.9.1 (2016-12-20)

* Bug fixes
  * Implement proper `input_value/3` callback

## v2.9.0 (2016-12-19)

* Enhancements
  * Add `img_tag/2` helper to `Phoenix.HTML.Tag`
  * Submit nearest form even if not direct descendent
  * Use more iodata for `tag/2` and `content_tag/3`
  * Add `input_value/3`, `input_id/2` and `input_name/2` as a unified API around the input (alongside `input_type/3` and `input_validations/2`)

## v2.8.0 (2016-11-15)

* Enhancements
  * Add `csrf_meta_tag/0` helper to `Phoenix.HTML.Tag`
  * Allow passing a `do:` option to `Phoenix.HTML.Link.button/2`

## v2.7.0 (2016-09-21)

* Enhancements
  * Render button tags for form submits and in the `button/2` function
  * Allow `submit/2` and `button/2` to receive `do` blocks
  * Support the `:multiple` option in `file_input/3`
  * Remove previously deprecated and unused `model` field

## v2.6.1 (2016-07-08)

* Enhancements
  * Remove warnings on v1.4

* Bug fixes
  * Ensure some contents are properly escaped as an integer
  * Ensure JavaScript data-submit events bubble up until it finds the proper parent

## v2.6.0 (2016-06-16)

* Enhancements
  * Raise helpful error when using invalid iodata
  * Inline date/time API with Elixir v1.3 Calendar types
  * Add `:insert_brs` option to `text_to_html/2`
  * Run on Erlang 19 without warnings

* Client-side changes
  * Use event delegation in `phoenix_html.js`
  * Drop IE8 support on `phoenix_html.js`

* Backwards incompatible changes
  * `:min`, `:sec` option in `Phoenix.HTML.Form` (`datetime_select/3` and `time_select/3`) are no longer supported. Use `:minute` or `:second` instead.

## v2.5.1 (2016-03-12)

* Bug fixes
  * Ensure multipart files work with inputs_for

## v2.5.0 (2016-01-28)

* Enhancements
  * Introduce `form.data` field instead of `form.model`. Currently those values are kept in sync then the form is built but `form.model` will be deprecated in the long term

## v2.4.0 (2016-01-21)

* Enhancements
  * Add `rel=nofollow` auto generation for non-get links
  * Introduce `:selected` option for `select`  and `multiple_select`

* Bug fixes
  * Fix safe engine incorrectly marking safe code as unsafe when last expression is `<% ... %>`

## v2.3.0 (2015-12-16)

* Enhancements
  * Add `escape_javascript/1`
  * Add helpful error message when using unknown `@inner` assign
  * Add `Phoenix.HTML.Format.text_to_html/2`

## v2.2.0 (2015-09-01)

* Bug fix
  * Allow the `:name` to be given in forms. For this, using `:name` to configure the underlying input name prefix has been deprecated in favor of `:as`

## v2.1.2 (2015-08-22)

* Bug fix
  * Do not include values in `password_input/3`

## v2.1.1 (2015-08-15)

* Enhancements
  * Allow nil in `raw/1`
  * Allow block options in `label/3`
  * Introduce `:skip_deleted` in `inputs_for/4`

## v2.1.0 (2015-08-06)

* Enhancements
  * Add an index field to forms to be used by `inputs_for/4` collections

## v2.0.1 (2015-07-31)

* Bug fix
  * Include web directory in Hex package

## v2.0.0 (2015-07-30)

* Enhancements
  * No longer generate onclick attributes.

    The main motivation for this is to provide support
    for Content Security Policy, which recommends
    disabling all inline scripts in a page.

    We took the opportunity to also add support for
    data-confirm in `link/2`.

## v1.4.0 (2015-07-26)

* Enhancements
  * Support `input_type/2` and `input_validations/2` as reflection mechanisms

## v1.3.0 (2015-07-23)

* Enhancements
  * Add `Phoenix.HTML.Form.inputs_for/4` support
  * Add multiple select support
  * Add reset input
  * Infer default text context for labels

## v1.2.1 (2015-06-02)

* Bug fix
  * Ensure nil parameters are not discarded when rendering input

## v1.2.0 (2015-05-30)

* Enhancements
  * Add `label/3` for generating a label tag within a form

## v1.1.0 (2015-05-20)

* Enhancements
  * Allow do/end syntax with `link/2`
  * Raise on missing assigns

## v1.0.1

* Bug fixes
  * Avoid variable clash in Phoenix.HTML engine buffers

## v1.0.0

* Enhancements
  * Provides an EEx engine with HTML safe rendering
  * Provides a `Phoenix.HTML.Safe` protocol
  * Provides a `Phoenix.HTML.FormData` protocol
  * Provides functions for generating tags, links and form builders in a safe way
