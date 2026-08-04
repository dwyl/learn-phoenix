# Changelog

## v0.26.2

* Introduces warning if plural messages are defined with the same singular
  message and conflicting plural messages.
* Improves performance by striping not required metadata when compiling the
  Gettext backend.

## v0.26.1

  * Address backwards incompatible changes in previous release

## v0.26.0

This release changes the way you use Gettext. We're not crazy: it does so because doing so makes it a lot faster to compile projects that use Gettext.
The changes *you* have to make to your code are minimal, and the old behavior is deprecated so that you will be guided on how to update.

The reason for this change is that it removes compile-time dependencies from modules that used to `import` a Gettext backend. In applications such as Phoenix applications, where every view and controller `import`s the Gettext backend, this change means a lot less compilation when you make translation changes!

Here's the new API. Now, instead of defining a Gettext backend (`use Gettext`) and then `import`ing that to use its macros, you need to:

  1. Define a Gettext backend with `use Gettext.Backend`
  1. Import and use its macros with `use Gettext, backend: MyApp.Gettext`.

### Before and After

Before this release, code using Gettext used to look something like this:

```elixir
defmodule MyApp.Gettext do
  use Gettext, otp_app: :my_app
end

defmodule MyAppWeb.Controller do
  import MyApp.Gettext
end
```

This creates a compile-time dependency for every module that `import`s the Gettext backend.

With this release, the above turns into:

```elixir
defmodule MyApp.Gettext do
  use Gettext.Backend, otp_app: :my_app
end

defmodule MyAppWeb.Controller do
  use Gettext, backend: MyApp.Gettext
end
```

We are also updating [Phoenix](https://github.com/phoenixframework/phoenix) generators to use the new API.

If you update Gettext and still use `use Gettext, otp_app: :my_app` to define a backend, Gettext will emit a warning now.

### Migration with Igniter

If your project is using [`igniter`](https://hex.pm/packages/igniter), you can run
[`mix igniter.update_gettext`](https://hexdocs.pm/igniter/Mix.Tasks.Igniter.UpdateGettext.html)
to automatically migrate to the new API.

### Detailed Changelog

This is a detailed list of the new things introduced in this release:

  * Add `Gettext.Macros`, which contains all the macros you know and love (`*gettext`). It also contains `*gettext_with_backend` variants to explicitly pass a backend at compile time and keep extraction working.
  * Document `lgettext/5` and `lngettext/7` callbacks in `Gettext.Backend`. These get generated in every Gettext backend.
  * Add the `Gettext.domain/0` type.

## v0.25.0

  * Run merging for `mix gettext.extract`'s POT files even if they are unchanged.
  * Allow Expo 1.0+.

## v0.24.0

  * Handle singular and plural messages with the same `msgid` as the same
    message.

    This change produces a `Expo.PO.DuplicateMessagesError` if you already have
    messages with the same singular `msgid`. This can be solved by calling the
    `expo.msguniq` mix task on your `.po` file:

    ```bash
    mix expo.msguniq \
      priv/gettext/LOCALE/LC_MESSAGES/DOMAIN.po \
      --output-file priv/gettext/LOCALE/LC_MESSAGES/DOMAIN.po
    ```

## v0.23.1

  * Use the Hex version of the excoveralls dependency.

## v0.23.0

  * Add the `:custom_flags_to_keep` Gettext option.

## v0.22.3

  * Fix a bug with extracting translations in Elixir 1.15.0+.

## v0.22.2

  * Use `Code.ensure_compiled/1` instead of `Code.ensure_loaded/1` for Elixir < 1.12 compatibility.
  * Ensure all modules are properly loaded for `mix gettext.merge`.
  * Fix a "protected" check when extracting translations.

## v0.22.1

  * Put correct `Plural-Forms` header on `gettext.merge` for the first time.
  * Fix extractor crash in case of conflicting backends.
  * Fix to use the correct plural forms for multiple languages.
  * Update expo to `~> 0.4.0` to fix issues with empty `msgstr`.

## v0.22.0

  * Deprecate (with a warning) the `--plural-forms` CLI option and the `:plural_forms` option in favor of `--plural-forms-header` and `:plural_forms_header`.
  * Supply the `Plural-Forms` header to `Gettext.Plural` callbacks.
  * Bump Expo requirement to `~> 0.3.0`.
  * Add the types:
    * `Gettext.Interpolation.bindings/0`
    * `Gettext.Error.t/0`
    * `Gettext.Plural.locale/0`
    * `Gettext.Plural.pluralization_context/0`
    * `Gettext.Plural.plural_info/0`
  * Add the optional callbacks `Gettext.Plural.init/1` and `Gettext.Plural.plural_forms_header/1`.

### Bug fixes

  * Fix `--check-up-to-date` with `msgid`s split in different ways.
  * Don't write the same file more than once in references when using `write_reference_line_numbers: false`.

## v0.21.0

### New features and improvements

  * Bump Elixir requirement to 1.11+.

  * Extract parsing and dumping of PO/POT files to the
    [expo](https://github.com/elixir-gettext/expo) library, and start depending
    on that.

  * Support marking messages as obsolete with the new `:on_obsolete` Gettext
    configuration option.

  * Add the `:write_reference_line_numbers` Gettext configuration option.

  * Save the previous messages when there's a fuzzy match, with the new
    `:store_previous_message_on_fuzzy_match` Gettext configuration option.

  * Change `:sort_by_msgid` to accept `false`, `:case_sensitive`, or
    `:case_insensitive` and deprecate the `true` value.

### Bug fixes

  * Sort messages independent of line splits when dumping PO files.

## v0.20.0

  * Allow `gettext_comment` to be invoked multiple times
  * Dump flags after references in PO files
  * Deprecate `compile.gettext` in favor of `__mix_recompile__?`

### Backwards incompatible changes

  * `handle_missing_translation(locale, domain, msgid, bindings)` callback
    signature was changed to `handle_missing_translation(locale, domain,
    msgctxt, msgid, bindings)` (it receives a new argument called `msgctxt`)

  * `handle_missing_plural_translation(locale, domain, msgid, msgid_plural, n,
    bindings)` callback signature was changed to
    `handle_missing_plural_translation(locale, domain, msgctxt, msgid,
    msgid_plural, n, bindings)` (it receives a new argument called `msgctxt`)

## v0.19.1

  * Fix warnings on Elixir v1.14+
  * Rename `ex-autogen` to `elixir-autogen` and make sure `elixir-autogen` is
    added to existing messages

## v0.19.0

  * Remove the `:one_module_per_locale` option in favor of  `:split_module_by`
    and `:split_module_compilation`
  * Make `Gettext.dngettext/6` bindings argument optional (effectively
    introducing `Gettext.dngettext/5`)
  * Preserve the `fuzzy` message flag when merging
  * Add the `--check-unextracted` flag to `mix gettext.extract`, which is useful
    in CI and similar
  * Place each message reference on its own line in extracted PO files
  * Make the interpolation module customizable via the `:interpolation`
    configuration option
  * Use a different flag to detect autogenerated messages (`ex-autogen`)
  * Update `gettext.extract` to correctly extract on recompilation for Elixir
    1.13+

## v0.18.2

  * Allow plural forms to be set for the `:gettext` application
  * Use `Application.compile_env/3` if available

## v0.18.1

  * Allow default domain to be configurable
  * Improve parallelism when compiling modules

## v0.18.0

  * Allow sorting strings by `msgid`
  * Add `:allowed_locales` to restrict the locales bundled in the backend

## v0.17.4

  * Do not change the return types of `*_noop` macros (regression in v0.17.2 and
    v0.17.3)
  * Fix dialyzer warnings

## v0.17.3

  * Add `lgettext/4` back which was removed in v0.17.2 - note `lgettext/4` is
    private API and may be removed in future once again

## v0.17.2

  * Support `pgettext`
  * Consider extracted comments when merging templates during extraction

## v0.17.1

  * Store the `msgctxt` value in message and dump it when dumping
    messages
  * Fix a bug when dumping references
  * Improve code generation
  * Preserve whitespace in message flags

## v0.17.0

  * Require Elixir 1.6 and later
  * Add stats reporting when merging PO files

## v0.16.1

  * Optimize default locale lookup

## v0.16.0

  * Fix bugs related to expanding arguments to Gettext macros
  * Fix a bug where you couldn't have filenames with colons in them in reference comments
  * Add `handle_missing_translation/4` and `handle_missing_plural_translation/6` callbacks to Gettext backends
  * Fix a bug in `mix gettext.extract`, which was ignoring the `--merge` option

## v0.15.0

  * Generate correct plural forms when dumping new messages in PO files
  * Fix a bug where we were losing translator comments for fuzzy-merged
    messages
  * Don't make an exact match when merging prevent later fuzzy matches
  * Allow multiple messages to fuzzy-match against the same message when
    merging
  * Bump the Elixir requirement to v1.4 and on

## v0.14.1

  * Copy flags from existing messages when merging messages

## v0.14.0

  * Introduce a global locale (per-process) for all Gettext backends
  * Warn when compiling and raise at runtime for missing plural forms
  * Separate flags with commas when dumping and parsing .pot files
  * Add support for extracted comments via `gettext_comment/1`
  * Require Elixir v1.3 and fix warnings
  * Improve compilation time of Gettext backends in roughly 20%
  * Add `:one_module_per_locale` for parallel compilation of backends (requires
    Elixir v1.6)
  * Use the `elixir-format` flag to mark autogenerated messages

## v0.13.1

  * Fix a bug with Dialyzer specs for the `Gettext.Backend.ngettext_noop/2` callback
  * Parse `msgctxt` entries in PO and POT files so that they don't cause syntax
    errors, but ignore them in the parsed result

## v0.13.0

  * Add the `gettext_noop/1`, `dgettext_noop/2`, `ngettext_noop/3`, and
    `dngettext_noop/4` macros to Gettext backends. These macros can be used to
    mark messages for extractions without translating the given string

## v0.12.2

  * Fix a bug where we failed miserably with a "no process" error when
    extracting messages without having the `:gettext` compiler run
  * Slightly revisit the indentation of subsequent literal strings in dumped
    PO(T) files; before, they were dumped one per line, indented one level more
    than the parent message, while now they're indented at the same level as
    the parent message

## v0.12.1

  * Ensure the Gettext application is started before running Mix tasks

## v0.12.0

  * Drop support for Elixir 1.1 and require ~> 1.2
  * Add `:compiler_po_wildcard` to explicitly choose the po files that are
    tracked by the compiler
  * Allow the developer to configure what happens when there are missing
    bindings in the message. The default has been changed to log and return
    the incomplete string instead of raising
  * Move the configuration for the `:gettext` application to compile-time config
    in `project/0` in `mix.exs` (under the `:gettext` key, with configuration
    options `:excluded_refs_from_purging`, `:compiler_po_wildcard` and
    `:fuzzy_threshold`)
  * Show the file name in syntax errors when running `mix gettext.extract` and
    `mix gettext.merge`
  * Don't print tokens as Erlang terms in syntax error when running `mix
    gettext.extract` and `mix gettext.merge`
  * Allow duplicate interpolation keys
  * Raise when the domain is not a binary at compile-time
  * Fix many dialyzer warnings
  * No longer traverse directories given to `gettext.merge` recursively (from
    now on `gettext.merge` expect specific locale directories)
  * Re enable the "compile" task in `mix gettext.extract`
  * Ensure messages are tracked to the proper child app when using umbrella
    apps

## v0.11.0

  * Polish so many docs!
  * Make an error in `Gettext.put_locale/2` clearer
  * Pluralize `x_Y` locales as `x`, but fail with
    `Gettext.Plural.UnknownLocaleError` for any other unknown locale
  * Add a `Gettext.Backend` behaviour (automatically implemented if a module
    calls `use Gettext`)
  * Allow whitelisting of references via the `:excluded_refs_from_purging` option
    in the `:gettext` application config

## v0.10.0

  * Emit warnings when the domain passed to one of the `*gettext` macros has
    slashes in it (as we don't support domains in subdirectories).
  * Discard dangling comments when parsing/dumping PO(T) files (dangling
    comments are comments that are not followed by a transaction they can be
    attached to).
  * Updated informative comments for newly generated PO/POT files.

## v0.9.0

  * Strip `##` comments from POT files when they're being merged into PO files;
    these comments are comments meant to be generated by tools or directed at
    developers (so they have no use for translators in PO files).
  * Add informative comments at the top of newly generated PO/POT files.
  * Add `Gettext.known_locales/1`
  * Fix a bug with PO parsing when the PO file starts with a
    [BOM](https://en.wikipedia.org/wiki/Byte_order_mark) character (which broke
    the parser, now a warning is issued).

## v0.8.0

  * Fix a bug with the `*gettext` macros, which raised an error when given
    compile-time strings in the form of `~s`/`~S` sigils.
  * Create missing locale directories (for example, `en/LC_MESSAGES`) when
    running the `gettext.merge` Mix task.
  * Fallback to default messages (that is, the `msgid`) when the `msgstr`
    (or one or more `msgstr` strings for plural messages) is empty.

## v0.7.0

  * When dumping PO files, dump as many references as possible on one line,
    wrapping at the 80th column
  * Parse multiple references in the same reference comment
  * Remove `Gettext.locale/0-1` and `Gettext.with_locale/2` in favour of
    `Gettext.get_locale/1`, `Gettext.put_locale/2`, and `Gettext.with_locale/3`
    which now work by setting/getting the locale on a per-backend basis (instead
    of a global one)
  * Remove the `:default_locale` config option for the `:gettext` application in
    favour of configuring the `:default_locale` for backends tied to their
    `:otp_app` (for example, `config :my_app, MyApp.Gettext, default_locale:
    "pt_BR"`)

## v0.6.1

  * Fix a bug with the `mix gettext.merge` task that was failing in Elixir
    v1.1.1 because `0.5 in 0..1` returns `false` with it

## v0.6.0

  * Add a `:flags` field to the `Gettext.PO.Translation` and
    `Gettext.PO.PluralTranslation` structs
  * Add support for fuzzy matching messages in `gettext.merge` and
    `gettext.extract --merge`
  * Add the `:fuzzy_threshold` configuration option for the `:gettext`
    application

## v0.5.0

  * Initial release
