# Changelog

## v1.1.0

* Add PO Parser Metadata Stripping

## v1.0.1

* Fix backslash escaping in `Expo.PO.compose/1`

## v1.0.0

* Fix compose output of extracted comments on plural messages

## v0.5.2

* Fix Elixir 1.16 deprecations

## v0.5.1

* Fix instruction commands for `Expo.PO.DuplicateMessagesError`.
* Fix `FunctionClauseError` in `msguniq` Mix task.
* Fix duplicated flags and comments for `Expo.Message.merge/2`.

## v0.5.0

  * Add `mix expo.msquniq` Mix task.
  * Detect duplicates for messages and *plural* messages.
  * Fix the `Expo.Message.msgctxt/0` type.
  * Add the `Expo.Message.split_lines/0` type.
  * Add `Expo.Message.merge/2`, `Expo.Message.Singular.merge/2`, and `Expo.Message.Plural.merge/2`.
  * Add `Expo.Message.Plural.key/1`.

## v0.4.1

  * Fix a bug with parsing multiline strings for plural messages
    ([issue](https://github.com/elixir-gettext/expo/issues/108)).

## v0.4.0

  * Strictly require at least one line of text in `msgid` and `msgstr`.
  * Fix `Expo.PO.compose/1` with only top comments and no headers.

## v0.3.0

  * Add `Expo.PluralForms` for functionality related to the `Plural-Forms`
    Gettext header.

## v0.2.0

  * Add support for previous message context (through `#| msgctxt "..."`
    comments).
  * Fix some issues with obsolete comments (`#~`) not parsing correctly in some
    cases.
