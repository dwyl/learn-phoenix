# Changelog

## v1.1.1 (2024-05-25)

  * Fix typespecs to avoid Dialyzer warnings
  * Do not list default values as part of received options
  * Mark structs in backticks for doc references
  * List deprecations in docs

## v1.1.0 (2023-12-13)

  * Add a `:type_spec` option to specify a quoted type spec for options.

## v1.0.2 (2023-04-21)

  * Improve typespec generation for ranges and structs.

## v1.0.1 (2023-03-13)

  * Make the `NimbleOptions.t/0` type *public* (instead of opaque). This helps with Dialyzer issues when ysing `NimbleOptions.new!/1` at compile time.

## v1.0.0 (2023-03-08)

  * Add support for a `{:struct, struct_name}` type specifier
  * Add support for the `:type_doc` option
  * Turn `t:NimbleOptions.t/0` into an *opaque* type

## v0.5.1 (2020-11-05)

  * Support generating typespecs for `:tuple`, `:map`, and `{:map, key, value}` options

## v0.5.0 (2020-09-20)

  * Support `:map` which accepts the same `:keys` specification as keyword lists
  * Normalize all error messages to include the key and expected value out of the box
  * Do not nest options when rendered in Markdown and make sure multiline content is properly indented
  * Handle \r\n style of line breaks in docs
  * Automatically add types to generated docs
  * Support lists of keyword lists in `:list`
  * Add the `:reference` option type
  * Add the `:tuple` option type

## v0.4.0 (2020-10-28)

  * Add support for all enumerables in `{:in, choices}` instead of just lists. You can now do things such as `{:in, 1..10}`.
  * Deprecate the `:rename_to` schema option and emit a warning when used.
  * Remove the `{:one_of, choices}` type which was deprecated in v0.3.3.

## v0.3.7 (2021-09-11)

  * Add `NimbleOptions.new!/1` to validate the schema once.

## v0.3.6 (2021-07-13)

  * Add `:float` type.
  * Fix docs generation when custom key type has no keys.

## v0.3.5 (2020-11-09)

  * Add support for the `{:list, subtype}` type.

## v0.3.4 (2020-11-05)

  * Support nested schemas in the `{:or, subtypes}` type as `{:or, [:string, keyword_list: [enabled: [type: :boolean]]]}`.
  * Improve validation of the return value of `{:custom, module, function, args}` functions.
  * Support options in `NimbleOptions.docs/2`. For now only the `:nest_level` option is supported.

## v0.3.3 (2020-11-02)

  * Add the `{:or, subtypes}` type.
  * Deprecate the `{:one_of, choices}` and replace it with `{:in, choices}`. Using `{:one_of, choices}` emits a warning now.

## v0.3.2 (2020-10-26)

  * Fix a small bug with docs for nested schemas.

## v0.3.1 (2020-10-25)

  * Return `:key` and `:value` on `%NimbleOptions.ValidationError{}` to allow programmatic use of errors.
  * Validate default values according to the specified type.

## v0.3.0 (2020-06-14)

  * **Breaking change**: return `{:error, %NimbleOptions.ValidationError{}}` tuples when there's a validation error in `NimbleOptions.validate/2` instead of `{:error, message}` (with `message` being a string). You can use `Exception.message/1` to turn the `NimbleOptions.ValidationError` struct into a string.
  * Add the `:pid` type.

## v0.2.1 (2020-05-08)

  * Add `NimbleOptions.validate!/2`.

## v0.2.0 (2020-04-11)

  * Change the behavior of `NimbleOptions.docs/1` to accept a normal schema and produce documentation for that.
  * Add support for `doc: false` as a schema option to hide an option or an option and its subsection.

## v0.1.0 (2020-04-07)

  * First release.
