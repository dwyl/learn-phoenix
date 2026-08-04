# Changelog

## v4.6.5

* Bug fixes
  * Unallow existing allowances when attempting to allow a Plug to access a connection

## v4.6.4

* Enhancements
  * Wrap raised Ecto exceptions so context is not lost
  * Do not override changeset actions

## v4.6.3

* Enhancements
  * Add prefix option to check repo status plug

* Bug fix
  * Fix map.field notation warning on Elixir 1.17

## v4.6.2

* Bug fix
  * Attach directories to Pending Migrations exception

## v4.6.1

* Bug fix
  * Ensure "Create database" action is shown when database is not available

## v4.6.0

* Enhancements
  * Return 400 for character encoding errors in Postgrex
  * Bump Elixir requirement to v1.11+

## v4.5.1

* Bug fix
  * Fix a regression on nested `inputs_for`

## v4.5.0

* Enhancements
  * Support Phoenix.HTML ~> 4.1
  * Use `to_form`'s `:action` as changeset action when passed

## v4.4.3

* Enhancements
  * Support Phoenix.HTML ~> 4.0

## v4.4.2

* Enhancements
  * Fix warning on undefined migration function when `ecto_sql` is missing
  * Support changesets with 3-arity cast function

## v4.4.1

* Enhancements
  * Allow migration_lock to be specified in check_repo_status
  * Support multiple repos on sandbox plug API
  * Support configuring multiple custom migration paths

## v4.4.0

This release bumps the requirement for Ecto and Phoenix.

* Enhancements
  * Trap exits when activating the test sandbox

## v4.3.0

* Enhancements
  * Support `:phoenix_html` v3.0

## v4.2.1

* Bug fixes
  * Only check for storage if we cannot check for migrations. This reduces the amount of operations for successful cases (which are the most common) and avoid issues for when we can't check the storage in the first place

## v4.2.0

* Enhancements
  * Support cast_assoc `with` MFA option on inputs_for

* Bug fixes
  * Do not treat `InvalidChangesetError` as 422 as those are not logged
  * Fix status code in check status exceptions to 503
  * Use text for floats and decimals as the `input_type` - numerics have many usability issues that led them to not be widely used

## v4.1.0

* Enhancements
  * Add `Phoenix.Ecto.CheckRepoStatus` plug

## v4.0.0

* Enhancements
  * Implement `Plug.Status` for `Ecto.StaleEntryError`
  * Support Ecto 3.0

## v3.4.0

* Enhancements
  * Use `:normal` formatting when converting `Decimal` to HTML safe
  * Ignore errors in case `changeset.action` is `:ignore`
  * Allow `:timeout` option on external sandbox
  * Extract and translate internal exception from `Ecto.SubQueryError`

## v3.3.0

* Enhancements
  * Support concurrent and transactional end-to-end tests for external HTTP clients using the new `:at` and `:repo` options to the `Phoenix.Ecto.SQL.Sandbox` plug

## v3.2.3

* Bug fixes
  * Make `phoenix_html` dependency optional once again

## v3.2.2

* Enhancements
  * Give `Ecto.InvalidChangesetError` plug_status 422

* Bug fixes
  * Do not raise for schemaless structs

## v3.2.1

* Bug fixes
  * Implement proper input_value/4 callback

## v3.2.0

* Enhancements
  * Depend on Phoenix.HTML ~> 2.9

## v3.1.0

* Enhancements
  * Depend on Ecto ~> 2.1 and support new `:naive_datetime` and `:utc_datetime` types

## v3.0.1

* Enhancements
  * Support non-struct data in changeset

## v3.0.0

* Enhancements
  * Add `Phoenix.Ecto.SQL.Sandbox` for concurrent acceptance tests with Phoenix and Ecto based on user-agent
  * Use the new sandbox based on user-agent
  * Depend on Phoenix.HTML ~> 2.6
  * Depend on Ecto ~> 2.0

* Bug fixes
  * Do not list errors if changeset has no action

## v2.0.0

* Enhancements
  * Depend on Ecto ~> 1.1

* Backwards incompatible changes
  * `f.errors` now returns a raw list of `changeset.errors` for the form's changeset which can be further translated with Phoenix' new Gettext support
  * No longer implement Poison protocol for `Ecto.Changeset`

## v1.2.0

* Enhancements
  * Depend on Ecto ~> 1.0
  * Depend on Phoenix.HTML ~> 2.2
  * Use the new `:as` option for naming inputs fields instead of `:name`

## v1.1.0

* Enhancements
  * Depend on Ecto ~> 0.15
  * Support `skip_deleted` in inputs_for
  * Support default values from data rather from `:default` option

## v1.0.0

* Enhancements
  * Depend on Phoenix.HTML ~> 2.1
  * Depend on Ecto ~> 0.15
  * Support associations on changesets

## v0.9.0

* Enhancements
  * Depend on Phoenix.HTML ~> 2.0

## v0.8.1

* Bug fix
  * Ensure we can encode decimals and floats from errors messages

## v0.8.0

* Enhancements
  * Depend on Phoenix.HTML ~> 1.4 (includes `input_type` and `input_validation` support)
  * Include embeds errors during JSON generation

## v0.7.0

* Enhancements
  * Depend on Phoenix.HTML ~> 1.3 (includes `inputs_for` support)

## v0.6.0

* Enhancements
  * Depend on Ecto ~> 0.14

## v0.5.0

* Enhancements
  * Depend on Ecto ~> 0.12

## v0.4.0

* Enhancements
  * Depend on phoenix_html as optional dependency instead of Phoenix
  * Depend on poison as optional dependency instead of Phoenix

## v0.3.2

* Bug fix
  * Ensure we interpolate `%{count}` in JSON encoding

## v0.3.1

* Enhancements
  * Implement Plug.Exception for Ecto exceptions

## v0.3.0

* Enhancements
  * Support Phoenix v0.11.0 errors entry in form data

## v0.2.0

* Enhancements
  * Implement `Phoenix.HTML.Safe` for `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`
  * Implement `Poison.Encoder` for `Ecto.Changeset`, `Decimal`, `Ecto.Date`, `Ecto.Time` and `Ecto.DateTime`

## v0.1.0

* Enhancements
  * Implement `Phoenix.HTML.FormData` for `Ecto.Changeset`
  * Implement `Phoenix.HTML.Safe` for `Decimal`
