defmodule Gettext do
  @moduledoc ~S"""
  The `Gettext` module provides a
  [gettext](https://www.gnu.org/software/gettext/)-based API for working with
  internationalized applications.

  ## Basic Overview

  When you use Gettext, you replace hardcoded user-facing text like this:

      "Hello world"

  with calls like this:

      gettext("Hello world")

  Here, the string `"Hello world"` serves two purposes:

    1. It's displayed by default (if no translation is specified in the current
       language). This means that, at the very least, switching from a hardcoded
       string to a Gettext call is harmless.

    2. It serves as the **message ID** to which translations will be mapped.

  An example translation workflow is as follows.

  First, call `mix gettext.extract` to extract `gettext()` calls to `.pot`
  ([Portable Object Template](https://www.gnu.org/software/gettext/manual/html_node/PO-Files.html))
  files, which are the base for all translations. These files are *templates*, which
  means they only contain message IDs, and not actual translated strings. POT files have
  entries like this:

      #: lib/myapp_web/live/hello_live.html.heex:2
      #, elixir-autogen, elixir-format
      msgid "Hello world"
      msgstr ""

  Then, call `mix gettext.merge priv/gettext` to update all
  locale-specific `.po` (Portable Object) files so that they include this message ID.
  Entries in PO files contain translations for their specific locale. For example,
  in a PO file for Italian, the entry above would look like this:

      #: lib/myapp_web/live/hello_live.html.heex:2
      #, elixir-autogen, elixir-format
      msgid "Hello world"
      msgstr "Ciao mondo"

  The English string is the `msgid` which is used to look up the
  correct Italian string.
  That's handy, because unlike a generic key like `site.greeting` (as some
  translations systems use), the message ID tells exactly what needs to be
  translated. This is easier to work with for translators, for example.

  But it raises a question: what if you change the original English string in the code?
  Does that break all translations, requiring manual edits everywhere? Not necessarily.
  After you run `mix gettext.extract` again, the next `mix gettext.merge` can
  do **fuzzy matching**.
  So, if you change `"Hello world"` to `"Hello world!"`, Gettext will see that the new
  message ID is similar to an existing `msgid`, and will do two things:

    1. It will update the `msgid` in all `.po` files to match the new text.

    2. It will mark those entries as "fuzzy"; this hints that a (probably human)
       translator should check whether the Italian translation of this string needs
       an update.

  The resulting change in the `.po` file is this (note the "fuzzy" annotation):

      #: lib/myapp_web/live/hello_live.html.heex:2
      #, elixir-autogen, elixir-format, fuzzy
      msgid "Hello world!"
      msgstr "Ciao mondo"

  This "fuzzy matching" behavior can be configured or disabled, but its
  existence makes updating translations to match changes in the base text easier.

  The rest of the documentation will cover the Gettext API in detail.

  ## Gettext API

  To use Gettext, you will need a **backend module** which stores and retrieves
  translations from PO files. You can create such a module by using `Gettext.Backend`:

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

  Now, you can import all the necessary translation macros (defined in `Gettext.Macros`)
  into any module by using `Gettext`:

      defmodule MyApp.SomeModule do
        use Gettext, backend: MyApp.Gettext

        def showcase_gettext do
          # Simple message
          gettext("Hello world")

          # Plural message
          ngettext(
            "Here is the string to translate",
            "Here are the strings to translate",
            3
          )

          # Domain-based message
          dgettext("errors", "Here is the error message to translate")

          # Context-based message
          pgettext("email", "Email text to translate")
        end
      end

  The arguments for the Gettext macros and their order can be derived from
  their names. For example, for [`dpgettext/4`](`Gettext.Macros.dpgettext/4`)
  the arguments are: `domain`, `context`, `msgid`, `bindings` (default to `%{}`).

  Messages are looked up from `.po` files. In the following sections we will
  explore exactly what are those files before we explore the "Gettext API" in
  detail.

  > #### Recent Updates {: .info}
  >
  > Before v0.26.0 of this library, the workflow described in this section
  > was slightly different. Check out [the
  > changelog](https://github.com/elixir-gettext/gettext/blob/main/CHANGELOG.md) for more
  > details, but the gist is that `use Gettext` used to define macros in the calling module.
  > This created heavy compile-time dependencies which would cause slow recompilation
  > in larger applications.

  ## Messages

  Messages are stored inside PO (Portable Object) files, with a `.po`
  extension. For example, this is a snippet from a PO file:

      # This is a comment
      msgid "Hello world!"
      msgstr "Ciao mondo!"

  PO files containing messages for an application must be stored in a
  directory (by default it's `priv/gettext`) that has the following structure:

      gettext directory
      └─ locale
         └─ LC_MESSAGES
            ├─ domain_1.po
            ├─ domain_2.po
            └─ domain_3.po

  Here, `locale` is the locale of the messages (for example, `en_US`),
  `LC_MESSAGES` is a fixed directory, and `domain_i.po` are PO files containing
  domain-scoped messages. For more information on domains, check out the
  "Domains" section below.

  A concrete example of such a directory structure could look like this:

      priv/gettext
      └─ en_US
      |  └─ LC_MESSAGES
      |     ├─ default.po
      |     └─ errors.po
      └─ it
         └─ LC_MESSAGES
            ├─ default.po
            └─ errors.po

  By default, Gettext expects messages to be stored under the `priv/gettext`
  directory of an application. This behaviour can be changed by specifying a
  `:priv` option when using `Gettext`:

      # Look for messages in my_app/priv/messages instead of
      # my_app/priv/gettext
      use Gettext.Backend,
        otp_app: :my_app,
        priv: "priv/messages"

  The messages directory specified by the `:priv` option should be a directory
  inside `priv/`, otherwise some things won't work as expected.

  ## Locale

  At runtime, all gettext-related functions and macros that do not explicitly
  take a locale as an argument read the locale from the backend and fall back
  to Gettext's default locale.

  `Gettext.put_locale/1` can be used to change the locale of all backends for
  the current Elixir process. That's the preferred mechanism for setting the
  locale at runtime. `Gettext.put_locale/2` can be used when you want to set the
  locale of one specific Gettext backend without affecting other Gettext
  backends.

  Similarly, `Gettext.get_locale/0` gets the locale for all backends in the
  current process. `Gettext.get_locale/1` gets the locale of a specific backend
  for the current process. Check their documentation for more information.

  Locales are expressed as strings (like `"en"` or `"fr"`); they can be
  arbitrary strings as long as they match a directory name. As mentioned above,
  the locale is stored **per-process** (in the process dictionary): this means
  that the locale must be set in every new process in order to have the right
  locale available for that process. Pay attention to this behaviour, since not
  setting the locale *will not* result in any errors when `Gettext.get_locale/0`
  or `Gettext.get_locale/1` are called; the default locale will be
  returned instead.

  To decide which locale to use, each gettext-related function in a given
  backend follows these steps:

    * if there is a backend-specific locale for the given backend for this
      process (see `put_locale/2`), use that, otherwise
    * if there is a global locale for this process (see `put_locale/1`), use
      that, otherwise
    * if there is a backend-specific default locale in the configuration for
      that backend's `:otp_app` (see the "Default locale" section below), use
      that, otherwise
    * use the default global Gettext locale (see the "Default locale" section
      below)

  ### Default locale

  The global Gettext default locale can be configured through the
  `:default_locale` key of the `:gettext` application:

      config :gettext, :default_locale, "fr"

  By default the global locale is `"en"`. See also `get_locale/0` and
  `put_locale/1`.

  If for some reason a backend requires a different `:default_locale`
  than all other backends, you can set the `:default_locale` inside the
  backend configuration, but this approach is generally discouraged as
  it makes it hard to track which locale each backend is using:

      config :my_app, MyApp.Gettext, default_locale: "fr"

  ## Gettext API

  There are two ways to use Gettext:

    * using macros from your own Gettext module, like `MyApp.Gettext`
    * using functions from the `Gettext` module

  These two approaches are different and each one has its own use case.

  ### Using macros

  Each module that calls `use Gettext.Backend` is usually referred to as a "Gettext
  backend", as it implements the `Gettext.Backend` behaviour. When a module then calls
  `use Gettext, backend: MyApp.Gettext`, all the macros defined in `Gettext.Macros`
  are imported into that module, such as:

    * [`gettext/2`](`Gettext.Macros.gettext/2`)
    * [`dgettext/3`](`Gettext.Macros.dgettext/3`)
    * [`pgettext/3`](`Gettext.Macros.pgettext/3`)

  Using macros is preferred as Gettext is able to automatically sync the
  messages in your code with PO files. This, however, imposes a constraint:
  arguments passed to any of these macros have to be strings **at compile
  time**. This means that they have to be string literals or something that
  expands to a string literal at compile time (for example, a module attribute like
  `@my_string "foo"`).

  These are all valid uses of the Gettext macros:

      Gettext.put_locale(MyApp.Gettext, "it")

      use Gettext, backend: MyApp.Gettext

      gettext("Hello world")
      #=> "Ciao mondo"

      @msgid "Hello world"
      gettext(@msgid)
      #=> "Ciao mondo"

  The `*gettext` macros raise an `ArgumentError` exception if they receive a
  `domain`, `msgctxt`, `msgid`, or `msgid_plural` that doesn't expand to a string
  *at compile time*:

      msgid = "Hello world"
      gettext(msgid)
      #=> ** (ArgumentError) msgid must be a string literal

  Using compile-time strings isn't always possible. For this reason,
  the `Gettext` module provides a set of functions as well.

  ### Using functions

  If compile-time strings cannot be used, the solution is to use the functions
  in the `Gettext` module instead of the macros described above. These functions
  perfectly mirror the macro API, but they all expect a Gettext backend module
  as the first argument.

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.put_locale(MyApp.Gettext, "pt_BR")

      msgid = "Hello world"
      Gettext.gettext(MyApp.Gettext, msgid)
      #=> "Olá mundo"

  While using functions from the `Gettext` module yields the same results as
  using macros (with the added benefit of dynamic arguments), all the
  compile-time features mentioned in the previous section are lost.

  ## Domains

  The [`dgettext`](`Gettext.Macros.dgettext/3`) and [`dngettext`](`Gettext.Macros.dngettext/5`)
  macros (and their function counterparts) also accept a *domain* as one
  of the arguments. The domain of a message is determined by the name of the
  PO file that contains that message. For example, the domain of
  messages in the `it/LC_MESSAGES/errors.po` file is `"errors"`, so those
  messages would need to be retrieved with `dgettext` or `dngettext`:

      dgettext("errors", "Error!")
      #=> "Errore!"

  When backend `gettext`, `ngettext`, or `pgettext` are used, the backend's
  default domain is used (which defaults to "default"). The `Gettext`
  functions accepting a backend (`gettext/3`, `ngettext/5`, and `pgettext/4`)
  _always_ use a domain of "default".

  ### Default Domain

  Each backend can be configured with a specific `:default_domain`
  that replaces `"default"` in `gettext/2`, `pgettext/3`, and `ngettext/4`
  for that backend.

      defmodule MyApp.Gettext do
        use Gettext.Backend,
          otp_app: :my_app,
          default_domain: "messages"
      end

      config :my_app, MyApp.Gettext, default_domain: "messages"

  ## Contexts

  The GNU Gettext implementation supports
  [*contexts*](https://www.gnu.org/software/gettext/manual/html_node/Contexts.html),
  which are a way to contextualize messages. For example, in English, the
  word "file" could be used both as a noun as well as a verb. Contexts can be used to
  solve similar problems: you could have a `imperative_verbs` context and a
  `nouns` context as to avoid ambiguity. The functions that handle contexts
  have a `p` in their name (to match the GNU Gettext API), and are `pgettext`,
  `dpgettext`, `pngettext`, and `dpngettext`. The "p" stands for "particular".

  ## Interpolation

  All `*gettext` functions and macros provided by Gettext support interpolation.
  Interpolation keys can be placed in `msgid`s or `msgid_plural`s with by
  enclosing them in `%{` and `}`, like this:

      "This is an %{interpolated} string"

  Interpolation bindings can be passed as an argument to all of the `*gettext`
  functions/macros. For example, given the following PO file for the `"it"`
  locale:

      msgid "Hello, %{name}!"
      msgstr "Ciao, %{name}!"

  interpolation can be done like follows:

      Gettext.put_locale(MyApp.Gettext, "it")
      gettext("Hello, %{name}!", name: "Meg")
      #=> "Ciao, Meg!"

  Interpolation keys that are in a string but not in the provided bindings
  result in an exception:

      gettext("Hello, %{name}!")
      #=> ** (Gettext.MissingBindingsError) ...

  Keys that are in the interpolation bindings but that don't occur in the string
  are ignored. Interpolations in Gettext are often expanded at compile time,
  ensuring a low performance cost when running them at runtime.

  ## Pluralization

  Pluralization in Gettext for Elixir works very similar to how pluralization
  works in GNU Gettext. The `*ngettext` functions/macros accept a `msgid`, a
  `msgid_plural`, and a count of elements; the right message is chosen based
  on the **pluralization rule** for the given locale.

  For example, given the following snippet of PO file for the `"it"` locale:

      msgid "One error"
      msgid_plural "%{count} errors"
      msgstr[0] "Un errore"
      msgstr[1] "%{count} errori"

  the `ngettext` macro can be used like this:

      Gettext.put_locale(MyApp.Gettext, "it")
      ngettext("One error", "%{count} errors", 3)
      #=> "3 errori"

  The `%{count}` interpolation key is a special key since it gets replaced by
  the number of elements argument passed to `*ngettext`, like if the `count: 3`
  key-value pair were in the interpolation bindings. Hence, never pass the
  `count` key in the bindings:

      # `count: 4` is ignored here
      ngettext("One error", "%{count} errors", 3, count: 4)
      #=> "3 errori"

  You can specify a "pluralizer" module via the `:plural_forms` option in the
  configuration for each Gettext backend.

      defmodule MyApp.Gettext do
        use Gettext.Backend,
          otp_app: :my_app,
          plural_forms: MyApp.PluralForms
      end

  To learn more about pluralization rules, plural forms and what they mean to
  Gettext check the documentation for `Gettext.Plural`.

  ## Missing messages

  When a message is missing in the specified locale (both with functions and
  with macros), the argument is returned:

    * in case of calls to `gettext`/`dgettext`/`pgettext`/`dpgettext`, the `msgid` argument is returned
      as is;
    * in case of calls to `ngettext`/`dngettext`/`pngettext`/`dpngettext`, the `msgid` argument is
      returned in case of a singular value and the `msgid_plural` is returned in
      case of a plural value (following the English pluralization rule).

  For example:

      Gettext.put_locale(MyApp.Gettext, "foo")
      gettext("Hey there")
      #=> "Hey there"
      ngettext("One error", "%{count} errors", 3)
      #=> "3 errors"

  ### Empty messages

  When a `msgstr` is empty (`""`), the message is considered missing and the
  behaviour described above for missing message is applied. A plural
  message is considered to have an empty `msgstr` if at least one
  message in the `msgstr` is empty.

  ## Compile-time features

  As mentioned above, using the Gettext macros (as opposed to functions) allows
  Gettext to operate on those messages *at compile-time*. This can be used
  to extract messages from the source code into POT (Portable Object Template)
  files automatically (instead of having to manually add messages to POT files
  when they're added to the source code). `mix gettext.extract` does exactly
  this: whenever there are new messages in the source code, running
  this task syncs the existing POT files with the changed code base.
  Read the documentation for `mix gettext.extract` for more information
  on the extraction process.

  POT files are just *template* files and the messages in them do not
  actually contain translated strings. A POT file looks like this:

      # The msgstr is empty
      msgid "hello, world"
      msgstr ""

  Whenever a POT file changes, it's likely that developers (or translators) will
  want to update the corresponding PO files for each locale. To do that, gettext
  provides the `gettext.merge` Mix task. For example, running:

      mix gettext.merge priv/gettext --locale pt_BR

  will update all the PO files in `priv/gettext/pt_BR/LC_MESSAGES` with the new
  version of the POT files in `priv/gettext`. Read more about the merging
  process in the documentation for `mix gettext.merge`.

  ## Configuration

  ### `:gettext` configuration

  The `:gettext` application supports the following configuration options:

    * `:default_locale` - a string which specifies the default global Gettext
      locale to use for all backends. See the "Locale" section for more
      information on backend-specific, global, and default locales.

  ### Backend configuration

  A **Gettext backend** supports some options to be configured. These options
  can be configured in two ways: either by passing them to `use Gettext` (hence
  at compile time):

      defmodule MyApp.Gettext do
        use Gettext.Backend, options
      end

  or by using Mix configuration, configuring the key corresponding to the
  backend in the configuration for your application:

      # For example, in config/config.exs
      config :my_app, MyApp.Gettext, options

  The `:otp_app` option (an atom representing an OTP application) has
  to always be present and has to be passed to `use Gettext` because it's used
  to determine the application to read the configuration of (`:my_app` in the
  example above); for this reason, `:otp_app` can't be configured via the Mix
  configuration. This option is also used to determine the application's
  directory where to search messages in.

  The following is a comprehensive list of supported options:

    * `:priv` - a string representing a directory where messages will be
      searched. The directory is relative to the directory of the application
      specified by the `:otp_app` option. It is recommended to always have
      this directory inside `"priv"`, otherwise some features won't work as expected.
      By default it's `"priv/gettext"`.

    * `:plural_forms` - a module which will act as a "pluralizer". For more
      information, look at the documentation for `Gettext.Plural`.

    * `:default_locale` - a string which specifies the default locale to use for
      the given backend.

    * `:split_module_by` - instead of bundling all locales into a single
      module, this option makes Gettext build internal modules per locale,
      per domain, or both. This reduces compilation times and beam file sizes
      for large projects. For example: `split_module_by: [:locale, :domain]`.

    * `:split_module_compilation` - control if compilation of split modules
      should happen in `:parallel` (the default) or `:serial`.

    * `:allowed_locales` - a list of locales to bundle in the backend.
      Defaults to all the locales discovered in the `:priv` directory.
      This option can be useful in development to reduce compile-time
      by compiling only a subset of all available locales.

    * `:interpolation` - the name of a module that implements the
      `Gettext.Interpolation` behaviour. Default: `Gettext.Interpolation.Default`

  ### Mix tasks configuration

  You can configure Gettext Mix tasks under the `:gettext` key in the
  configuration returned by `project/0` in `mix.exs`:

      def project() do
        [app: :my_app,
         # ...
         gettext: [...]]
      end

  The following is a list of the supported configuration options:

    * `:fuzzy_threshold` - the default threshold for the Jaro distance measuring
      the similarity of messages. Look at the documentation for the `mix
      gettext.merge` task (`Mix.Tasks.Gettext.Merge`) for more information on
      fuzzy messages.

    * `:excluded_refs_from_purging` - a regex that is matched against message
      references. Gettext will preserve all messages in all POT files that
      have a matching reference. You can use this pattern to prevent Gettext from
      removing messages that you have extracted using another tool.

    * `:custom_flags_to_keep` - a list of custom flags that will be kept for
      existing messages during a merge. Gettext always keeps the `fuzzy` flag.
      If you want to keep the `elixir-format` flag, which is also commonly
      used by Gettext, add it to this list. Available since v0.23.0.

    * `:write_reference_comments` - a boolean that specifies whether reference
      comments should be written when outputting PO(T) files. If this is `false`,
      reference comments will not be written when extracting messages or merging
      messages, and the ones already found in files will be discarded.

    * `:write_reference_line_numbers` - a boolean that specifies whether file
      reference comments include line numbers when outputting PO(T) files.
      Defaults to `true`.

    * `:sort_by_msgid` - modifies the sorting behavior. Can be either `nil` (the default),
      `:case_sensitive`, or `:case_insensitive`.
      By default or if `nil`, the order of existing messages in a POT file is kept and new
      messages are appended to the file. If `:sort_by_msgid` is set to `:case_sensitive`,
      existing and new messages will be mixed and sorted alphabetically by msgid.
      If set to `:case_insensitive`, the same applies but the sorting is case insensitive.
      *Note*: this option also supports `true` and `false` for backwards compatibility,
      but these values are deprecated as of v0.21.0.

    * `:on_obsolete` - controls what happens when obsolete messages are found.
      If `:mark_as_obsolete`, messages are kept and marked as obsolete.
      If `:delete`, obsolete messages are deleted. Defaults to `:delete`.

    * `:store_previous_message_on_fuzzy_match` - a boolean that controls
      whether to store the previous message text in case of a fuzzy match.
      Defaults to `false`.

  """

  require Gettext.Macros
  alias Gettext.MissingBindingsError

  @type locale :: binary
  @type backend :: module
  @type bindings :: map() | Keyword.t()

  @typedoc """
  A Gettext domain.

  See [*Domains*](#module-domains) in the module documentation for more information.
  """
  @typedoc since: "0.26.0"
  @type domain() :: :default | binary()

  defguardp is_domain(domain) when domain == :default or is_binary(domain)

  @doc false
  defmacro __using__(opts) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    case Keyword.keyword?(opts) && Keyword.fetch(opts, :backend) do
      {:ok, backend} ->
        case Macro.expand(backend, __CALLER__) do
          backend when is_atom(backend) and backend not in [nil, false, true] ->
            # We need to store the module backend at expansion time because of extraction
            Module.put_attribute(__CALLER__.module, :__gettext_backend__, backend)

            quote do
              import Gettext.Macros
            end

          _ ->
            raise ArgumentError,
                  "the :backend option on \"use Gettext\" expects the backend " <>
                    "to be a literal atom/alias/module, got: #{Macro.to_string(backend)}"
        end

      _other ->
        # TODO: remove this once we stop supporting the old way of defining backends.
        IO.warn(
          """
          defining a Gettext backend by calling

              use Gettext, otp_app: ...

          is deprecated. To define a backend, call:

              use Gettext.Backend, otp_app: :my_app

          Then, instead of importing your backend, call this in your module:

              use Gettext, backend: MyApp.Gettext
          """,
          Macro.Env.stacktrace(__CALLER__)
        )

        quote do
          use Gettext.Backend, unquote(opts)
          @before_compile {Gettext.Compiler, :generate_macros}
        end
    end
  end

  defp expand_alias({:__aliases__, _, _} = als, env) do
    Macro.expand(als, %{env | function: {:__gettext__, 1}})
  end

  defp expand_alias(other, _env) do
    other
  end

  @doc """
  Gets the global Gettext locale for the current process.

  This function returns the value of the global Gettext locale for the current
  process. This global locale is shared between all Gettext backends; if you
  want backend-specific locales, see `get_locale/1` and `put_locale/2`. If the
  global Gettext locale is not set, this function returns the default global
  locale (configurable in the configuration for the `:gettext` application, see
  the module documentation for more information).

  ## Examples

      Gettext.get_locale()
      #=> "en"

  """
  @doc section: :locale
  @spec get_locale() :: locale
  def get_locale() do
    with nil <- Process.get(Gettext) do
      # If this is not set by the user, it's still set in mix.exs (to "en").
      Application.fetch_env!(:gettext, :default_locale)
    end
  end

  @doc """
  Sets the global Gettext locale for the current process.

  The locale is stored in the process dictionary. `locale` must be a string; if
  it's not, an `ArgumentError` exception is raised.

  The return value is the previous value of the current
  process's locale.

  ## Examples

      Gettext.put_locale("pt_BR")
      #=> nil
      Gettext.get_locale()
      #=> "pt_BR"

  """
  @doc section: :locale
  @spec put_locale(locale) :: locale | nil
  def put_locale(locale) when is_binary(locale), do: Process.put(Gettext, locale)

  def put_locale(locale),
    do: raise(ArgumentError, "put_locale/1 only accepts binary locales, got: #{inspect(locale)}")

  @doc """
  Gets the locale for the current process and the given backend.

  This function returns the value of the locale for the current process and the
  given `backend`. If there is no locale for the current process and the given
  backend, then either the global Gettext locale (if set), or the default locale
  for the given backend, or the global default locale is returned. See the
  "Locale" section in the module documentation for more information.

  ## Examples

      Gettext.get_locale(MyApp.Gettext)
      #=> "en"

  """
  @doc section: :locale
  @spec get_locale(backend) :: locale
  def get_locale(backend) do
    with nil <- Process.get(backend),
         nil <- Process.get(Gettext) do
      backend.__gettext__(:default_locale)
    end
  end

  @doc """
  Sets the locale for the current process and the given `backend`.

  The locale is stored in the process dictionary. `locale` must be a string; if
  it's not, an `ArgumentError` exception is raised.

  The return value is the previous value of the current
  process's locale.

  ## Examples

      Gettext.put_locale(MyApp.Gettext, "pt_BR")
      #=> nil
      Gettext.get_locale(MyApp.Gettext)
      #=> "pt_BR"

  """
  @doc section: :locale
  @spec put_locale(backend, locale) :: locale | nil
  def put_locale(backend, locale) when is_binary(locale), do: Process.put(backend, locale)

  def put_locale(_backend, locale),
    do: raise(ArgumentError, "put_locale/2 only accepts binary locales, got: #{inspect(locale)}")

  @doc """
  Returns the message of the given string with a given context in the given domain.

  The string is translated by the `backend` module.

  The translated string is interpolated based on the `bindings` argument. For
  more information on how interpolation works, refer to the documentation of the
  `Gettext` module.

  If the message for the given `msgid` is not found, the `msgid`
  (interpolated if necessary) is returned.

  ## Examples

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.put_locale(MyApp.Gettext, "it")

      Gettext.dpgettext(MyApp.Gettext, "errors", "user error", "Invalid")
      #=> "Non valido"

      Gettext.dgettext(MyApp.Gettext, "errors", "signup form", "%{name} is not a valid name", name: "Meg")
      #=> "Meg non è un nome valido"

  """
  @doc section: :translation
  @spec dpgettext(module, domain, binary | nil, binary, bindings) :: binary
  def dpgettext(backend, domain, msgctxt, msgid, bindings \\ %{})

  def dpgettext(backend, domain, msgctxt, msgid, bindings) when is_list(bindings) do
    dpgettext(backend, domain, msgctxt, msgid, Map.new(bindings))
  end

  def dpgettext(backend, domain, msgctxt, msgid, bindings)
      when is_atom(backend) and is_domain(domain) and is_binary(msgid) and is_map(bindings) do
    domain = domain_or_default(backend, domain)
    locale = get_locale(backend)
    result = backend.lgettext(locale, domain, msgctxt, msgid, bindings)
    handle_backend_result(result, backend, locale, domain, msgctxt, msgid)
  end

  @doc """
  Returns the message of the given string in the given domain.

  The string is translated by the `backend` module.

  The translated string is interpolated based on the `bindings` argument. For
  more information on how interpolation works, refer to the documentation of the
  `Gettext` module.

  If the message for the given `msgid` is not found, the `msgid`
  (interpolated if necessary) is returned.

  ## Examples

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.put_locale(MyApp.Gettext, "it")

      Gettext.dgettext(MyApp.Gettext, "errors", "Invalid")
      #=> "Non valido"

      Gettext.dgettext(MyApp.Gettext, "errors", "%{name} is not a valid name", name: "Meg")
      #=> "Meg non è un nome valido"

      Gettext.dgettext(MyApp.Gettext, "alerts", "nonexisting")
      #=> "nonexisting"

  """
  @doc section: :translation
  @spec dgettext(module, domain, binary, bindings) :: binary
  def dgettext(backend, domain, msgid, bindings \\ %{}) do
    dpgettext(backend, domain, nil, msgid, bindings)
  end

  @doc """
  Returns the message of the given string with the given context

  The string is translated by the `backend` module.

  The translated string is interpolated based on the `bindings` argument. For
  more information on how interpolation works, refer to the documentation of the
  `Gettext` module.

  If the message for the given `msgid` is not found, the `msgid`
  (interpolated if necessary) is returned.

  ## Examples

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.put_locale(MyApp.Gettext, "it")

      Gettext.pgettext(MyApp.Gettext, "user-interface", "Invalid")
      #=> "Non valido"

      Gettext.pgettext(MyApp.Gettext, "user-interface", "%{name} is not a valid name", name: "Meg")
      #=> "Meg non è un nome valido"

      Gettext.pgettext(MyApp.Gettext, "alerts-users", "nonexisting")
      #=> "nonexisting"
  """
  @doc section: :translation
  @spec pgettext(module, binary, binary, bindings) :: binary
  def pgettext(backend, msgctxt, msgid, bindings \\ %{}) do
    dpgettext(backend, "default", msgctxt, msgid, bindings)
  end

  @doc """
  Returns the message of the given string in the `"default"` domain.

  Works exactly like:

      Gettext.dgettext(backend, "default", msgid, bindings)

  """
  @doc section: :translation
  @spec gettext(module, binary, bindings) :: binary
  def gettext(backend, msgid, bindings \\ %{}) do
    dgettext(backend, "default", msgid, bindings)
  end

  @doc """
  Returns the pluralized message of the given string with a given context in the given domain.

  The string is translated and pluralized by the `backend` module.

  The translated string is interpolated based on the `bindings` argument. For
  more information on how interpolation works, refer to the documentation of the
  `Gettext` module.

  If the message for the given `msgid` and `msgid_plural` is not found, the
  `msgid` or `msgid_plural` (based on `n` being singular or plural) is returned
  (interpolated if necessary).

  ## Examples

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.dpngettext(MyApp.Gettext, "errors", "user error", "Error", "%{count} errors", 3)
      #=> "3 errori"
      Gettext.dpngettext(MyApp.Gettext, "errors", "user error", "Error", "%{count} errors", 1)
      #=> "Errore"

  """
  @doc section: :translation
  @spec dpngettext(module, domain, binary | nil, binary, binary, non_neg_integer, bindings) ::
          binary
  def dpngettext(backend, domain, msgctxt, msgid, msgid_plural, n, bindings \\ %{})

  def dpngettext(backend, domain, msgctxt, msgid, msgid_plural, n, bindings)
      when is_list(bindings) do
    dpngettext(backend, domain, msgctxt, msgid, msgid_plural, n, Map.new(bindings))
  end

  def dpngettext(backend, domain, msgctxt, msgid, msgid_plural, n, bindings)
      when is_atom(backend) and is_domain(domain) and is_binary(msgid) and is_binary(msgid_plural) and
             is_integer(n) and n >= 0 and is_map(bindings) do
    domain = domain_or_default(backend, domain)
    locale = get_locale(backend)
    result = backend.lngettext(locale, domain, msgctxt, msgid, msgid_plural, n, bindings)
    handle_backend_result(result, backend, locale, domain, msgctxt, msgid)
  end

  @doc """
  Returns the pluralized message of the given string in the given domain.

  The string is translated and pluralized by the `backend` module.

  The translated string is interpolated based on the `bindings` argument. For
  more information on how interpolation works, refer to the documentation of the
  `Gettext` module.

  If the message for the given `msgid` and `msgid_plural` is not found, the
  `msgid` or `msgid_plural` (based on `n` being singular or plural) is returned
  (interpolated if necessary).

  ## Examples

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

      Gettext.dngettext(MyApp.Gettext, "errors", "Error", "%{count} errors", 3)
      #=> "3 errori"
      Gettext.dngettext(MyApp.Gettext, "errors", "Error", "%{count} errors", 1)
      #=> "Errore"

  """
  @doc section: :translation
  @spec dngettext(module, domain, binary, binary, non_neg_integer, bindings) :: binary
  def dngettext(backend, domain, msgid, msgid_plural, n, bindings \\ %{}),
    do: dpngettext(backend, domain, nil, msgid, msgid_plural, n, bindings)

  @doc """
  Returns the pluralized message of the given string with a given context
  in the `"default"` domain.

  Works exactly like:

      Gettext.dpngettext(backend, "default", context, msgid, msgid_plural, n, bindings)

  """
  @doc section: :translation
  @spec pngettext(module, binary, binary, binary, non_neg_integer, bindings) :: binary
  def pngettext(backend, msgctxt, msgid, msgid_plural, n, bindings),
    do: dpngettext(backend, "default", msgctxt, msgid, msgid_plural, n, bindings)

  @doc """
  Returns the pluralized message of the given string in the `"default"`
  domain.

  Works exactly like:

      Gettext.dngettext(backend, "default", msgid, msgid_plural, n, bindings)

  """
  @doc section: :translation
  @spec ngettext(module, binary, binary, non_neg_integer, bindings) :: binary
  def ngettext(backend, msgid, msgid_plural, n, bindings \\ %{}) do
    dngettext(backend, "default", msgid, msgid_plural, n, bindings)
  end

  @doc """
  Runs `fun` with the global Gettext locale set to `locale`.

  This function just sets the global Gettext locale to `locale` before running
  `fun` and sets it back to its previous value afterwards. Note that
  `put_locale/2` is used to set the locale, which is thus set only for the
  current process (keep this in mind if you plan on spawning processes inside
  `fun`).

  The value returned by this function is the return value of `fun`.

  ## Examples

      Gettext.put_locale("fr")

      gettext("Hello world")
      #=> "Bonjour monde"

      Gettext.with_locale("it", fn ->
        gettext("Hello world")
      end)
      #=> "Ciao mondo"

      gettext("Hello world")
      #=> "Bonjour monde"

  """
  @doc section: :locale
  @spec with_locale(locale, (-> result)) :: result when result: var
  def with_locale(locale, fun) when is_binary(locale) and is_function(fun) do
    previous_locale = Process.get(Gettext)
    Gettext.put_locale(locale)

    try do
      fun.()
    after
      if previous_locale do
        Gettext.put_locale(previous_locale)
      else
        Process.delete(Gettext)
      end
    end
  end

  @doc """
  Runs `fun` with the Gettext locale set to `locale` for the given `backend`.

  This function just sets the Gettext locale for `backend` to `locale` before
  running `fun` and sets it back to its previous value afterwards. Note that
  `put_locale/2` is used to set the locale, which is thus set only for the
  current process (keep this in mind if you plan on spawning processes inside
  `fun`).

  The value returned by this function is the return value of `fun`.

  ## Examples

      Gettext.put_locale(MyApp.Gettext, "fr")

      gettext("Hello world")
      #=> "Bonjour monde"

      Gettext.with_locale(MyApp.Gettext, "it", fn ->
        gettext("Hello world")
      end)
      #=> "Ciao mondo"

      gettext("Hello world")
      #=> "Bonjour monde"

  """
  @doc section: :locale
  @spec with_locale(backend(), locale(), (-> result)) :: result when result: var
  def with_locale(backend, locale, fun)
      when is_atom(backend) and is_binary(locale) and is_function(fun) do
    previous_locale = Process.get(backend)
    Gettext.put_locale(backend, locale)

    try do
      fun.()
    after
      if previous_locale do
        Gettext.put_locale(backend, previous_locale)
      else
        Process.delete(backend)
      end
    end
  end

  @doc """
  Returns all the locales for which PO files exist for the given `backend`.

  If the messages directory for the given backend doesn't exist, then an
  empty list is returned.

  ## Examples

  With the following backend:

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

  and the following messages directory:

      my_app/priv/gettext
      ├─ en
      ├─ it
      └─ pt_BR

  then:

      Gettext.known_locales(MyApp.Gettext)
      #=> ["en", "it", "pt_BR"]

  """
  @doc section: :locale
  @spec known_locales(backend()) :: [locale()]
  def known_locales(backend) when is_atom(backend) do
    backend.__gettext__(:known_locales)
  end

  defp handle_backend_result({:ok, string}, _backend, _locale, _domain, _msgctxt, _msgid) do
    string
  end

  defp handle_backend_result({:default, string}, _backend, _locale, _domain, _msgctxt, _msgid) do
    string
  end

  defp handle_backend_result(
         {:missing_bindings, incomplete, missing},
         backend,
         locale,
         domain,
         msgctxt,
         msgid
       ) do
    exception = %MissingBindingsError{
      backend: backend,
      locale: locale,
      domain: domain,
      msgctxt: msgctxt,
      msgid: msgid,
      missing: missing
    }

    backend.handle_missing_bindings(exception, incomplete)
  end

  defp domain_or_default(backend, :default), do: backend.__gettext__(:default_domain)
  defp domain_or_default(_backend, domain) when is_binary(domain), do: domain
end
