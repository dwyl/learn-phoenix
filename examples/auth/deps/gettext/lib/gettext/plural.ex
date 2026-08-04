defmodule Gettext.Plural do
  @moduledoc """
  Behaviour and default implementation for finding plural forms in given
  locales.

  This module both defines the `Gettext.Plural` behaviour and provides a default
  implementation for it.

  ## Plural Forms

  > For a given language, there is a grammatical rule on how to change words
  > depending on the number qualifying the word. Different languages can have
  > different rules.
  [[source]](https://udn.realityripple.com/docs/Mozilla/Localization/Localization_and_Plurals)

  Such grammatical rules define a number of **plural forms**. For example,
  English has two plural forms: one for when there is just one element (the
  *singular*) and another one for when there are zero or more than one elements
  (the *plural*). There are languages which only have one plural form and there
  are languages which have more than two.

  In GNU Gettext (and in Gettext for Elixir), plural forms are represented by
  increasing 0-indexed integers. For example, in English `0` means singular and
  `1` means plural.

  The goal of this module is to determine, given a locale:

    * how many plural forms exist in that locale (`nplurals/1`);

    * to what plural form a given number of elements belongs to in that locale
      (`plural/2`).

  ## Default Implementation

  `Gettext.Plural` provides a default implementation of a plural module. Most
  common languages used on Earth should be covered by this default implementation. If
  custom pluralization rules are needed (for example, to add additional
  languages) a different plural module can be specified when creating a Gettext
  backend. For example, pluralization rules for the Elvish language could be
  added as follows:

      defmodule MyApp.Plural do
        @behaviour Gettext.Plural

        def nplurals("elv"), do: 3

        def plural("elv", 0), do: 0
        def plural("elv", 1), do: 1
        def plural("elv", _), do: 2

        # Fall back to Gettext.Plural
        defdelegate nplurals(locale), to: Gettext.Plural
        defdelegate plural(locale, n), to: Gettext.Plural
      end

  The mathematical expressions used in this module to determine the plural form
  of a given number of elements are taken from [this
  page](http://localization-guide.readthedocs.org/en/latest/l10n/pluralforms.html#f2)
  as well as from [Mozilla's guide on "Localization and
  plurals"](https://udn.realityripple.com/docs/Mozilla/Localization/Localization_and_Plurals).

  ## Changing Implementations

  Once you have defined your custom plural forms module, you can use it
  in two ways. You can set it for all Gettext backends in your
  configuration:

      # For example, in config/config.exs
      config :gettext, :plural_forms, MyApp.Plural

  or you can set it for each specific backend when you call `use Gettext`:

      defmodule MyApp.Gettext do
        use Gettext.Backend,
          otp_app: :my_app,
          plural_forms: MyApp.Plural
      end

  > #### Compile-time Configuration {: .warning}
  >
  > Set `:plural_forms` in your `config/config.exs` and
  > not in `config/runtime.exs`, as Gettext reads this option when
  > compiling your backends.

  Task such as `mix gettext.merge` use the plural
  backend configured under the `:gettext` application, so in general
  the global configuration approach is preferred.

  Some tasks also allow the number of plural forms to be given
  explicitly, for example:

      mix gettext.merge priv/gettext --locale=gsw_CH --plural-forms=2

  ## Unknown Locales

  Trying to call `Gettext.Plural` functions with unknown locales will result in
  a `Gettext.Plural.UnknownLocaleError` exception.

  ## Language and Territory

  Often, a locale is composed as a language and territory pair, such as
  `en_US`. The default implementation for `Gettext.Plural` handles `xx_YY` by
  forwarding it to `xx` (except for *just Brazilian Portuguese*, `pt_BR`, which
  is not forwarded to `pt` as pluralization rules differ slightly). We treat the
  underscore as a separator according to
  [ISO 15897](https://en.wikipedia.org/wiki/ISO/IEC_15897). Sometimes, a dash `-` is
  used as a separator (for example [BCP47](https://en.wikipedia.org/wiki/IETF_language_tag)
  locales use this as in `en-US`): this is *not forwarded* to `en` in the default
  `Gettext.Plural` (and it will raise an `Gettext.Plural.UnknownLocaleError` exception
  if there are no messages for `en-US`). We recommend defining a custom plural forms
  module that replaces `-` with `_` if needed.

  ## Examples

  An example of the plural form of a given number of elements in the Polish
  language:

      iex> Gettext.Plural.plural("pl", 1)
      0
      iex> Gettext.Plural.plural("pl", 2)
      1
      iex> Gettext.Plural.plural("pl", 5)
      2
      iex> Gettext.Plural.plural("pl", 112)
      2

  As expected, `nplurals/1` returns the possible number of plural forms:

      iex> Gettext.Plural.nplurals("pl")
      3

  """

  alias Expo.Messages

  # Types

  @typedoc """
  A locale passed to `c:plural/2`.
  """
  @typedoc since: "0.22.0"
  @type locale() :: String.t()

  @typedoc """
  The context passed to the optional `c:init/1` callback.

  If `:plural_forms_header` is present, it contains the contents
  of the `Plural-Forms` Gettext header.
  """
  @typedoc since: "0.22.0"
  @type pluralization_context() :: %{
          required(:locale) => locale(),
          optional(:plural_forms_header) => String.t()
        }

  @typedoc """
  The term that the optional `c:init/1` callback returns.
  """
  @typedoc since: "0.22.0"
  @type plural_info() :: term()

  ## Behaviour definition

  @doc """
  Should initialize the context for `c:nplurals/1` and `c:plural/2`.

  This callback should perform all preparations for the provided locale, which
  is part of the pluralization context (see `t:pluralization_context/0`). For
  example, you can use this callback to parse the `Plural-Forms` header and
  determine pluralization rules for the locale.

  If defined, Gettext calls this callback *once* at compile time. If not defined,
  the returned `plural_info` will be equals to the locale found in
  `pluralization_context`.

  ## Examples

      defmodule MyApp.Plural do
        @behaviour Gettext.Plural

        @impl true
        def init(%{locale: _locale, plural_forms_header: header}) do
          {nplurals, rule} = parse_plural_forms_header(header)

          # This is what other callbacks can use to determine the plural.
          {nplurals, rule}
        end

        @impl true
        def nplurals({_locale, nplurals, _rule}), do: nplurals

        # ...
      end

  """
  @doc since: "0.22.0"
  @callback init(pluralization_context()) :: plural_info()

  @doc """
  Should return the number of possible plural forms in the given `locale`.
  """
  @callback nplurals(plural_info()) :: pos_integer()

  @doc """
  Should return the plural form in the given `locale` for the given `count` of
  elements.
  """
  @callback plural(plural_info(), count :: integer()) :: plural_form :: non_neg_integer()

  @doc """
  Should return the value of the `Plural-Forms` header for the given `locale`,
  if present.

  If the value of the `Plural-Forms` header is unavailable for any reason, this
  function should return `nil`.

  This callback is optional. If it's not defined, the fallback returns:

      "nplurals={nplurals};"

  """
  @doc since: "0.22.0"
  @callback plural_forms_header(locale()) :: String.t() | nil

  @optional_callbacks init: 1, plural_forms_header: 1

  defmodule UnknownLocaleError do
    @moduledoc """
    Raised when a pluralized module doesn't know how to handle a locale.

    ## Examples

        raise Gettext.Plural.UnknownLocaleError, "en-US"

    """

    defexception [:message]

    def exception(locale) when is_binary(locale) do
      message = """
      unknown locale #{inspect(locale)}. If this is a locale you need to handle,
      consider using a custom pluralizer module instead of the default
      Gettext.Plural. You can read more about this on the Gettext docs at
      https://hexdocs.pm/gettext/Gettext.Plural.html
      """

      %__MODULE__{message: message}
    end
  end

  # Behaviour implementation.

  # Default implementation of the init/1 callback, in case the user uses
  # Gettext.Plural as their plural forms module.
  @doc false
  def init(context)

  def init(%{locale: locale, plural_forms_header: plural_forms_header}) do
    case Expo.PluralForms.parse(plural_forms_header) do
      {:ok, plural_forms} ->
        {locale, plural_forms}

      {:error, _reason} ->
        message_about_header =
          case Expo.PluralForms.plural_form(locale) do
            {:ok, plural_form} ->
              """

              For the #{inspect(locale)} locale, you can use the following header:

              #{Expo.PluralForms.to_string(plural_form)}
              """

            :error ->
              ""
          end

        # Fall back to parsing headers such as "nplurals=3", without the "plural=..." part.
        # TODO: remove this in v0.24.0
        with "nplurals=" <> rest <- String.trim(plural_forms_header),
             {plural_forms, _rest} <- Integer.parse(rest) do
          IO.warn("""
          Plural-Forms headers in the form "nplurals=<int>" (without the "plural=<rule>" part \
          following) are invalid and support for them will be removed in future Gettext \
          versions. Make sure to use a complete Plural-Forms header, which also specifies \
          the pluralization rules, or remove the Plural-Forms header completely. If you \
          do the latter, Gettext will use its built-in pluralization rules for the languages \
          it knows about (see Gettext.Plural).#{message_about_header}\
          """)

          {locale, plural_forms}
        else
          _other -> locale
        end
    end
  end

  def init(%{locale: locale}), do: locale

  # Number of plural forms.

  @doc """
  Default implementation of the `c:nplurals/1` callback.
  """
  def nplurals(locale)

  # TODO: this is a fallback for headers such as "nplurals=x", without "plural=...".
  # We should remove support for these at some point.
  def nplurals({_locale, nplurals}) when is_integer(nplurals) do
    nplurals
  end

  # If the nplurals was provided, we don't need to look at the locale.
  def nplurals({_locale, plural_forms}) do
    plural_forms.nplurals
  end

  def nplurals(locale) do
    case Expo.PluralForms.plural_form(locale) do
      {:ok, plural_form} -> plural_form.nplurals
      :error -> recall_if_territory_or_raise(locale, &nplurals/1)
    end
  end

  @doc """
  Default implementation of the `c:plural/2` callback.
  """
  def plural(locale, count)

  # TODO: this is a fallback for headers such as "nplurals=x", without "plural=...".
  # We should remove support for these at some point.
  def plural({locale, nplurals}, count) when is_integer(nplurals) do
    plural(locale, count)
  end

  def plural({_locale, plural_form}, count) do
    Expo.PluralForms.index(plural_form, count)
  end

  def plural(locale, count) do
    case Expo.PluralForms.plural_form(locale) do
      {:ok, plural_form} -> Expo.PluralForms.index(plural_form, count)
      :error -> recall_if_territory_or_raise(locale, &plural(&1, count))
    end
  end

  def plural_forms_header(locale) do
    case Expo.PluralForms.plural_form(locale) do
      {:ok, plural_form} -> Expo.PluralForms.to_string(plural_form)
      :error -> recall_if_territory_or_raise(locale, &plural_forms_header(&1))
    end
  rescue
    UnknownLocaleError -> nil
  end

  defp recall_if_territory_or_raise(locale, fun) do
    case String.split(locale, "_", parts: 2, trim: true) do
      [lang, _territory] -> fun.(lang)
      _other -> raise UnknownLocaleError, locale
    end
  end

  @doc false
  def plural_info(locale, messages_struct, plural_mod) do
    Code.ensure_compiled!(plural_mod)

    if function_exported?(plural_mod, :init, 1) do
      pluralization_context =
        case IO.iodata_to_binary(Messages.get_header(messages_struct, "Plural-Forms")) do
          "" -> %{locale: locale}
          plural_forms -> %{locale: locale, plural_forms_header: plural_forms}
        end

      plural_mod.init(pluralization_context)
    else
      locale
    end
  end

  @doc false
  def plural_forms_header_impl(locale, messages_struct, plural_mod) do
    Code.ensure_compiled!(plural_mod)

    plural_forms_header =
      if function_exported?(plural_mod, :plural_forms_header, 1) do
        plural_mod.plural_forms_header(locale)
      end

    if plural_forms_header do
      plural_forms_header
    else
      nplurals = plural_mod.nplurals(plural_info(locale, messages_struct, plural_mod))
      "nplurals=#{nplurals}"
    end
  end
end
