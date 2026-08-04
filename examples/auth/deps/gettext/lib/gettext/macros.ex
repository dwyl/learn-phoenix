defmodule Gettext.Macros do
  @moduledoc """
  Macros used by Gettext to provide the gettext family of functions.

  *Available since v0.26.0.*

  Macros enable users to use gettext and get **automatic extraction** of translations.
  See `Gettext` for more information.

  The macros in this module *that don't end with `_with_backend`* are imported
  every time you call:

      use Gettext, backend: MyApp.Gettext

  ### Explicit backend

  If you need to use the macros here with an explicit backend and you want extraction
  to work, you can use the `_with_backend` versions of the macros in this module explicitly
  instead.

      defmodule MyApp.Gettext do
        use Gettext, otp_app: :my_app
      end

      defmodule MyApp.Controller do
        require Gettext.Macros

        def index(conn, _params) do
          Gettext.Macros.gettext_with_backend(MyApp.Gettext, "Hello, world!")
        end
      end

  """

  @moduledoc since: "0.26.0"

  alias Gettext.Extractor

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      dpgettext_noop("errors", "Home page", "Error found!")
      #=> "Error found!"

  """
  defmacro dpgettext_noop(domain, msgctxt, msgid) do
    extract_singular_translation(__CALLER__, backend(__CALLER__), domain, msgctxt, msgid)
  end

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      dgettext_noop("errors", "Error found!")
      #=> "Error found!"

  """
  defmacro dgettext_noop(domain, msgid) do
    extract_singular_translation(__CALLER__, backend(__CALLER__), domain, _msgctxt = nil, msgid)
  end

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      gettext_noop("Error found!")
      #=> "Error found!"

  """
  defmacro gettext_noop(msgid) do
    extract_singular_translation(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      _msgctxt = nil,
      msgid
    )
  end

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      pgettext_noop("Error found!", "Home page")
      #=> "Error found!"

  """
  defmacro pgettext_noop(msgid, context) do
    extract_singular_translation(__CALLER__, backend(__CALLER__), :default, context, msgid)
  end

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      dpngettext_noop("errors", "Home page", "Error found!", "Errors found!")
      #=> "Error found!"

  """
  defmacro dpngettext_noop(domain, msgctxt, msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend(__CALLER__),
      domain,
      msgctxt,
      msgid,
      msgid_plural
    )
  end

  @doc """
  Marks the given message for extraction and returns
  `{msgid, msgid_plural}`.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value of this macro is `{msgid,
  msgid_plural}`.

  ## Examples

      my_fun = fn {msgid, msgid_plural} ->
        # do something with msgid and msgid_plural
      end

      my_fun.(dngettext_noop("errors", "One error", "%{count} errors"))

  """
  defmacro dngettext_noop(domain, msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend(__CALLER__),
      domain,
      _msgctxt = nil,
      msgid,
      msgid_plural
    )
  end

  @doc """
  Marks the given message for extraction and returns it unchanged.

  This macro can be used to mark a message for extraction when `mix
  gettext.extract` is run. The return value is the given string, so that this
  macro can be used seamlessly in place of the string to extract.

  ## Examples

      pngettext_noop("Home page", "Error found!", "Errors found!")
      #=> "Error found!"

  """
  defmacro pngettext_noop(msgctxt, msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      msgctxt,
      msgid,
      msgid_plural
    )
  end

  @doc """
  Same as `dngettext_noop("default", msgid, mgsid_plural)`, but will use a
  per-backend configured default domain if provided.
  """
  defmacro ngettext_noop(msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      _msgctxt = nil,
      msgid,
      msgid_plural
    )
  end

  @doc """
  Translates the given `msgid` with a given context (`msgctxt`) in the given `domain`.

  `bindings` is a map of bindings to support interpolation.

  See also `Gettext.dpgettext/5`.
  """
  defmacro dpgettext(domain, msgctxt, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      domain,
      msgctxt,
      msgid,
      bindings
    )
  end

  @doc """
  Translates the given `msgid` in the given `domain`.

  `bindings` is a map of bindings to support interpolation.

  See also `Gettext.dgettext/4`.
  """
  defmacro dgettext(domain, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      domain,
      _msgctxt = nil,
      msgid,
      bindings
    )
  end

  @doc """
  Translates the given `msgid` with the given context (`msgctxt`).

  `bindings` is a map of bindings to support interpolation.

  See also `Gettext.pgettext/4`.
  """
  defmacro pgettext(msgctxt, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      msgctxt,
      msgid,
      bindings
    )
  end

  @doc """
  Same as `dgettext("default", msgid, %{})`, but will use a per-backend
  configured default domain if provided.

  See also `Gettext.gettext/3`.
  """
  defmacro gettext(msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      _msgctxt = nil,
      msgid,
      bindings
    )
  end

  @doc """
  Translates the given plural message (`msgid` + `msgid_plural`) with the given context (`msgctxt`)
  in the given `domain`.

  `n` is an integer used to determine how to pluralize the
  message. `bindings` is a map of bindings to support interpolation.

  See also `Gettext.dpngettext/7`.
  """
  defmacro dpngettext(domain, msgctxt, msgid, msgid_plural, n, bindings \\ Macro.escape(%{})) do
    plural_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      domain,
      msgctxt,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Translates the given plural message (`msgid` + `msgid_plural`) in the
  given `domain`.

  `n` is an integer used to determine how to pluralize the
  message. `bindings` is a map of bindings to support interpolation.

  See also `Gettext.dngettext/6`.
  """
  defmacro dngettext(domain, msgid, msgid_plural, n, bindings \\ Macro.escape(%{})) do
    plural_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      domain,
      _msgctxt = nil,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Same as `dngettext("default", msgid, msgid_plural, n, bindings)`, but will
  use a per-backend configured default domain if provided.

  See also `Gettext.ngettext/5`.
  """
  defmacro ngettext(msgid, msgid_plural, n, bindings \\ Macro.escape(%{})) do
    plural_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      _msgctxt = nil,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Translates the given plural message (`msgid` + `msgid_plural`) with the given context (`msgctxt`).

  `n` is an integer used to determine how to pluralize the
  message. `bindings` is a map of bindings to support interpolation.

  See also `Gettext.pngettext/6`.
  """
  defmacro pngettext(msgctxt, msgid, msgid_plural, n, bindings \\ Macro.escape(%{})) do
    plural_extract_and_translate(
      __CALLER__,
      backend(__CALLER__),
      _domain = :default,
      msgctxt,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Stores an "extracted comment" for the next message.

  This macro can be used to add comments (Gettext refers to such
  comments as *extracted comments*) to the next message that will
  be extracted. Extracted comments will be prefixed with `#.` in POT
  files.

  Calling this function multiple times will accumulate the comments;
  when another Gettext macro (such as `gettext/2`) is called,
  the comments will be extracted and attached to that message, and
  they will be flushed so as to start again.

  This macro always returns `:ok`.

  ## Examples

      gettext_comment("The next message is awesome")
      gettext_comment("Another comment for the next message")
      gettext("The awesome message")

  """
  defmacro gettext_comment(comment) do
    comment = expand_to_binary(comment, "comment", __CALLER__)
    append_extracted_comment(comment)
    :ok
  end

  ## Singular no-op macros (with backend).

  @doc """
  Same as `dpgettext_noop/3`, but takes an explicit backend.
  """
  defmacro dpgettext_noop_with_backend(backend, domain, msgctxt, msgid) do
    extract_singular_translation(__CALLER__, backend, domain, msgctxt, msgid)
  end

  @doc """
  Same as `dgettext_noop/2`, but takes an explicit backend.
  """
  defmacro dgettext_noop_with_backend(backend, domain, msgid) do
    extract_singular_translation(__CALLER__, backend, domain, _msgctxt = nil, msgid)
  end

  @doc """
  Same as `pgettext_noop/2`, but takes an explicit backend.
  """
  defmacro pgettext_noop_with_backend(backend, msgctxt, msgid) do
    extract_singular_translation(__CALLER__, backend, _domain = :default, msgctxt, msgid)
  end

  @doc """
  Same as `gettext_noop/1`, but takes an explicit backend.
  """
  defmacro gettext_noop_with_backend(backend, msgid) do
    extract_singular_translation(__CALLER__, backend, _domain = :default, _msgctxt = nil, msgid)
  end

  ## Plural no-op macros (with backend).

  @doc """
  Same as `dpngettext_noop/4`, but takes an explicit backend.
  """
  defmacro dpngettext_noop_with_backend(backend, domain, msgctxt, msgid, msgid_plural) do
    extract_plural_translation(__CALLER__, backend, domain, msgctxt, msgid, msgid_plural)
  end

  @doc """
  Same as `dngettext_noop/3`, but takes an explicit backend.
  """
  defmacro dngettext_noop_with_backend(backend, domain, msgid, msgid_plural) do
    extract_plural_translation(__CALLER__, backend, domain, _msgctxt = nil, msgid, msgid_plural)
  end

  @doc """
  Same as `pngettext_noop/3`, but takes an explicit backend.
  """
  defmacro pngettext_noop_with_backend(backend, msgctxt, msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend,
      _domain = :default,
      msgctxt,
      msgid,
      msgid_plural
    )
  end

  @doc """
  Same as `ngettext_noop/2`, but takes an explicit backend.
  """
  defmacro ngettext_noop_with_backend(backend, msgid, msgid_plural) do
    extract_plural_translation(
      __CALLER__,
      backend,
      _domain = :default,
      _msgctxt = nil,
      msgid,
      msgid_plural
    )
  end

  ## Singular macros (with backend).

  @doc """
  Same as `dpgettext/4`, but takes an explicit backend.
  """
  defmacro dpgettext_with_backend(backend, domain, msgctxt, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(__CALLER__, backend, domain, msgctxt, msgid, bindings)
  end

  @doc """
  Same as `dgettext/3`, but takes an explicit backend.
  """
  defmacro dgettext_with_backend(backend, domain, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(__CALLER__, backend, domain, _msgctxt = nil, msgid, bindings)
  end

  @doc """
  Same as `pgettext/3`, but takes an explicit backend.
  """
  defmacro pgettext_with_backend(backend, msgctxt, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend,
      _domain = :default,
      msgctxt,
      msgid,
      bindings
    )
  end

  @doc """
  Same as `gettext/2`, but takes an explicit backend.
  """
  defmacro gettext_with_backend(backend, msgid, bindings \\ Macro.escape(%{})) do
    singular_extract_and_translate(
      __CALLER__,
      backend,
      _domain = :default,
      _msgctxt = nil,
      msgid,
      bindings
    )
  end

  @doc """
  Same as `dpngettext/6`, but takes an explicit backend.
  """
  defmacro dpngettext_with_backend(
             backend,
             domain,
             msgctxt,
             msgid,
             msgid_plural,
             n,
             bindings \\ Macro.escape(%{})
           ) do
    plural_extract_and_translate(
      __CALLER__,
      backend,
      domain,
      msgctxt,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Same as `dngettext/5`, but takes an explicit backend.
  """
  defmacro dngettext_with_backend(
             backend,
             domain,
             msgid,
             msgid_plural,
             n,
             bindings \\ Macro.escape(%{})
           ) do
    plural_extract_and_translate(
      __CALLER__,
      backend,
      domain,
      _msgctxt = nil,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Same as `pngettext/5`, but takes an explicit backend.
  """
  defmacro pngettext_with_backend(
             backend,
             msgctxt,
             msgid,
             msgid_plural,
             n,
             bindings \\ Macro.escape(%{})
           ) do
    plural_extract_and_translate(
      __CALLER__,
      backend,
      _domain = :default,
      msgctxt,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  @doc """
  Same as `ngettext/4`, but takes an explicit backend.
  """
  defmacro ngettext_with_backend(backend, msgid, msgid_plural, n, bindings \\ Macro.escape(%{})) do
    plural_extract_and_translate(
      __CALLER__,
      backend,
      _domain = :default,
      _msgctxt = nil,
      msgid,
      msgid_plural,
      n,
      bindings
    )
  end

  ## Helpers

  defp extract_singular_translation(env, backend, domain, msgctxt, msgid) do
    backend = expand_backend(backend, env)
    domain = expand_domain(domain, env)
    msgid = expand_to_binary(msgid, "msgid", env)
    msgctxt = expand_to_binary(msgctxt, "msgctxt", env)

    if Extractor.extracting?() do
      Extractor.extract(
        env,
        backend,
        domain,
        msgctxt,
        msgid,
        get_and_flush_extracted_comments()
      )
    end

    msgid
  end

  defp extract_plural_translation(env, backend, domain, msgctxt, msgid, msgid_plural) do
    backend = expand_backend(backend, env)
    domain = expand_domain(domain, env)
    msgid = expand_to_binary(msgid, "msgid", env)
    msgctxt = expand_to_binary(msgctxt, "msgctxt", env)
    msgid_plural = expand_to_binary(msgid_plural, "msgid_plural", env)

    if Extractor.extracting?() do
      Extractor.extract(
        env,
        backend,
        domain,
        msgctxt,
        {msgid, msgid_plural},
        get_and_flush_extracted_comments()
      )
    end

    {msgid, msgid_plural}
  end

  defp singular_extract_and_translate(env, backend, domain, msgctxt, msgid, bindings) do
    domain = expand_domain(domain, env)
    msgid = extract_singular_translation(env, backend, domain, msgctxt, msgid)

    quote do
      Gettext.dpgettext(
        unquote(backend),
        unquote(domain),
        unquote(msgctxt),
        unquote(msgid),
        unquote(bindings)
      )
    end
  end

  defp plural_extract_and_translate(
         env,
         backend,
         domain,
         msgctxt,
         msgid,
         msgid_plural,
         n,
         bindings
       ) do
    domain = expand_domain(domain, env)

    {msgid, msgid_plural} =
      extract_plural_translation(env, backend, domain, msgctxt, msgid, msgid_plural)

    quote do
      Gettext.dpngettext(
        unquote(backend),
        unquote(domain),
        unquote(msgctxt),
        unquote(msgid),
        unquote(msgid_plural),
        unquote(n),
        unquote(bindings)
      )
    end
  end

  defp expand_domain(:default, _env), do: :default
  defp expand_domain(domain, env), do: expand_to_binary(domain, "domain", env)

  defp backend(%Macro.Env{} = env) do
    Module.get_attribute(env.module, :__gettext_backend__) ||
      raise """
      in order to use Gettext.Macros, you must:

          use Gettext, backend: ...

      """
  end

  defp expand_to_binary(term, what, %Macro.Env{} = env)
       when what in ~w(domain msgctxt msgid msgid_plural comment) do
    raiser = fn term ->
      gettext_module = Module.get_attribute(env.module, :__gettext_backend__)

      raise ArgumentError, """
      Gettext macros expect message keys (msgid and msgid_plural),
      domains, and comments to expand to strings at compile-time, but the given #{what}
      doesn't. This is what the macro received:

      #{inspect(term)}

      Dynamic messages should be avoided as they limit Gettext's
      ability to extract messages from your source code. If you are
      sure you need dynamic lookup, you can use the functions in the Gettext
      module:

          string = "hello world"
          Gettext.gettext(#{if(gettext_module, do: inspect(gettext_module), else: "backend")}, string)
      """
    end

    # We support nil too in order to fall back to a nil context and always use the *p
    # variants of the Gettext macros.
    case Macro.expand(term, env) do
      term when is_binary(term) or is_nil(term) ->
        term

      {:<<>>, _, pieces} = term ->
        if Enum.all?(pieces, &is_binary/1), do: Enum.join(pieces), else: raiser.(term)

      other ->
        raiser.(other)
    end
  end

  defp expand_backend(term, %Macro.Env{} = env) do
    case Macro.expand(term, env) do
      term when is_atom(term) and term not in [nil, false, true] ->
        term

      _other ->
        raise ArgumentError, """
        Gettext.Macros macros (that end with "_with_backend") expect the backend argument
        to be an atom at compile-time, but the given term doesn't. This is what the macro
        received:

        #{inspect(term)}

        Dynamic messages should be avoided as they limit Gettext's
        ability to extract messages from your source code. If you are
        sure you need dynamic lookup, you can use the functions in the Gettext
        module:

            string = "hello world"
            Gettext.gettext(backend, string)
        """
    end
  end

  defp append_extracted_comment(comment) do
    existing = Process.get(:gettext_comments, [])
    Process.put(:gettext_comments, [" " <> comment | existing])
    :ok
  end

  defp get_and_flush_extracted_comments() do
    Enum.reverse(Process.delete(:gettext_comments) || [])
  end
end
