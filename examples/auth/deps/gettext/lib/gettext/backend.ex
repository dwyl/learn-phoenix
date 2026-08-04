defmodule Gettext.Backend do
  @moduledoc """
  Defines a Gettext backend.

  ## Usage

  A Gettext **backend** must `use` this module.

      defmodule MyApp.Gettext do
        use Gettext.Backend, otp_app: :my_app
      end

  Using this module generates all the callbacks required by the `Gettext.Backend`
  behaviour into the module that uses it. For more options and information,
  see `Gettext`.

  > #### `use Gettext.Backend` Is a Recent Feature {: .info}
  >
  > Before version v0.26.0, you could only `use Gettext` to generate a backend.
  >
  > Version v0.26.0 changes the way backends work so that now a Gettext backend
  > must `use Gettext.Backend`, while to use the functions in the backend you
  > will do `use Gettext, backend: MyApp.Gettext`.
  """

  defmacro __using__(opts) do
    # TODO: From Elixir v1.13 onwards, use compile_env and remove this if.
    env_fun = if function_exported?(Module, :attributes_in, 1), do: :compile_env, else: :get_env

    quote do
      require Logger

      opts = unquote(opts)
      otp_app = Keyword.fetch!(opts, :otp_app)

      @gettext_opts opts
                    |> Keyword.merge(Application.unquote(env_fun)(otp_app, __MODULE__, []))
                    |> Keyword.put_new(:interpolation, Gettext.Interpolation.Default)

      @interpolation Keyword.fetch!(@gettext_opts, :interpolation)

      @before_compile Gettext.Compiler

      def handle_missing_bindings(exception, incomplete) do
        _ = Logger.error(Exception.message(exception))
        incomplete
      end

      defoverridable handle_missing_bindings: 2

      def handle_missing_translation(_locale, domain, _msgctxt, msgid, bindings) do
        Gettext.Compiler.warn_if_domain_contains_slashes(domain)

        with {:ok, interpolated} <- @interpolation.runtime_interpolate(msgid, bindings),
             do: {:default, interpolated}
      end

      def handle_missing_plural_translation(
            _locale,
            domain,
            _msgctxt,
            msgid,
            msgid_plural,
            n,
            bindings
          ) do
        Gettext.Compiler.warn_if_domain_contains_slashes(domain)
        string = if n == 1, do: msgid, else: msgid_plural
        bindings = Map.put(bindings, :count, n)

        with {:ok, interpolated} <- @interpolation.runtime_interpolate(string, bindings),
             do: {:default, interpolated}
      end

      defoverridable handle_missing_translation: 5, handle_missing_plural_translation: 7
    end
  end

  @doc """
  Default handling for missing bindings.

  This function is called when there are missing bindings in a message. It
  takes a `Gettext.MissingBindingsError` struct and the message with the
  wrong bindings left as is with the `%{}` syntax.

  For example, if something like this is called:

      gettext("Hello %{name}, your favorite color is %{color}", name: "Jane", color: "blue")

  and our `it/LC_MESSAGES/default.po` looks like this:

      msgid "Hello %{name}, your favorite color is %{color}"
      msgstr "Ciao %{name}, il tuo colore preferito è %{colour}" # (typo)

  then Gettext will call:

      MyApp.Gettext.handle_missing_bindings(exception, "Ciao Jane, il tuo colore preferito è %{colour}")

  where `exception` is a struct that looks like this:

      %Gettext.MissingBindingsError{
        backend: MyApp.Gettext,
        domain: "default",
        locale: "it",
        msgid: "Ciao %{name}, il tuo colore preferito è %{colour}",
        bindings: [:colour],
      }

  The return value of the `c:handle_missing_bindings/2` callback is used as the
  translated string that the message macros and functions return.

  The default implementation for this function uses `Logger.error/1` to warn
  about the missing binding and returns the translated message with the
  incomplete bindings.

  This function can be overridden. For example, to raise when there are missing
  bindings:

      def handle_missing_bindings(exception, _incomplete) do
        raise exception
      end

  """
  @callback handle_missing_bindings(Gettext.MissingBindingsError.t(), binary) ::
              binary | no_return

  @doc """
  Default handling for messages with a missing message.

  When a Gettext function/macro is called with a string to translate
  into a locale but that locale doesn't provide a message for that
  string, this callback is invoked. `msgid` is the string that Gettext
  tried to translate.

  This function should return `{:ok, translated}` if a message can be
  fetched or constructed for the given string. If you cannot find a
  message, it should return `{:default, translated}`, where the
  translated string defaults to the interpolated msgid. You can, however,
  customize the default to, for example, pick the message from the
  default locale. The important is to return `:default` instead of `:ok`
  whenever the result does not quite match the requested locale.

  Earlier versions of this library provided a callback without msgctxt.
  Users implementing that callback will still get the same results,
  but they are encouraged to switch to the new 5-argument version.
  """
  @callback handle_missing_translation(
              Gettext.locale(),
              domain :: String.t(),
              msgctxt :: String.t(),
              msgid :: String.t(),
              bindings :: map()
            ) ::
              {:ok, String.t()} | {:default, String.t()} | {:missing_bindings, String.t(), [atom]}

  @doc """
  Default handling for plural messages with a missing message.

  Same as `c:handle_missing_translation/5`, but for plural messages.
  In this case, `n` is the number used for pluralizing the translated string.

  Earlier versions of this library provided a callback without msgctxt.
  Users implementing that callback will still get the same results,
  but they are encouraged to switch to the new 7-argument version.
  """
  @callback handle_missing_plural_translation(
              Gettext.locale(),
              domain :: String.t(),
              msgctxt :: String.t(),
              msgid :: String.t(),
              msgid_plural :: String.t(),
              n :: non_neg_integer(),
              bindings :: map()
            ) ::
              {:ok, String.t()} | {:default, String.t()} | {:missing_bindings, String.t(), [atom]}

  @doc """
  Translates a message.

  See `Gettext.gettext/3` for more information.
  """
  @doc since: "0.26.0"
  @callback lgettext(
              Gettext.locale(),
              domain :: String.t(),
              msgctxt :: String.t() | nil,
              msgid :: String.t(),
              bindings :: map()
            ) ::
              {:ok, String.t()} | {:default, String.t()} | {:missing_bindings, String.t(), [atom]}

  @doc """
  Translates a plural message.

  See `Gettext.ngettext/5` for more information.
  """
  @doc since: "0.26.0"
  @callback lngettext(
              Gettext.locale(),
              domain :: String.t(),
              msgctxt :: String.t() | nil,
              msgid :: String.t(),
              msgid_plural :: String.t(),
              n :: non_neg_integer(),
              bindings :: map()
            ) ::
              {:ok, String.t()} | {:default, String.t()} | {:missing_bindings, String.t(), [atom]}
end
