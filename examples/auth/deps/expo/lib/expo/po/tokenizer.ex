defmodule Expo.PO.Tokenizer do
  @moduledoc false

  # This module is responsible for turning a chunk of text (a string) into a
  # list of tokens. For what "token" means, see the docs for `tokenize/1`.

  @type line :: pos_integer

  @type token ::
          {:str_lines, line, [binary]}
          | {:plural_form, line, non_neg_integer}
          | {:msgid, line}
          | {:msgid_plural, line}
          | {:msgstr, line}
          | {:msgctxt, line}
          | {:obsolete_msgid, line}
          | {:obsolete_msgid_plural, line}
          | {:obsolete_msgstr, line}
          | {:obsolete_msgctxt, line}
          | {:comment, line, binary}
          | {:previous, line}
          | {:eof, line}

  # In this list of keywords *the order matters* because a function clause is
  # generated for each keyword, and keywords have to be followed by whitespace.
  # `msgid_plural` would cause an error if it didn't come before `msgid`.
  # Also note that the `msgstr` keyword is missing here since it can be also
  # followed by a plural form (for example, `[1]`).
  @string_keywords ~w(
    msgid_plural
    msgid
    msgctxt
  )

  @whitespace [?\n, ?\t, ?\r, ?\s]
  @whitespace_no_nl [?\t, ?\r, ?\s]
  @escapable_chars [?", ?n, ?t, ?r, ?\\]

  @doc """
  Converts a string into a list of tokens.

  A "token" is a tuple formed by:

    * the `:str` tag or a keyword tag (like `:msgid`)
    * the line the token is at
    * the value of the token if the token has a value (for example, a `:str`
      token will have the contents of the string as a value)

  Some examples of tokens are:

    * `{:msgid, 33}`
    * `{:str, 6, "foo"}`

  """
  @spec tokenize(binary, [Expo.PO.parse_option()]) ::
          {:ok, [token]} | {:error, pos_integer, binary}
  def tokenize(str, opts \\ []) do
    strip_meta? = Keyword.get(opts, :strip_meta, false)
    tokenize_line(str, _line = 1, strip_meta?, _tokens_acc = [])
  end

  # Reverse str_lines strings.
  defp postprocess_tokens([{:str_lines, line, strings} | rest]) do
    [{:str_lines, line, Enum.reverse(strings)} | postprocess_tokens(rest)]
  end

  # These make parsing easier.
  for kw <- [:msgid, :msgid_plural, :msgctxt, :msgstr] do
    defp postprocess_tokens([{:obsolete, _line}, {unquote(kw), line} | rest]) do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      [{:"obsolete_#{unquote(kw)}", line} | postprocess_tokens(rest)]
    end
  end

  # There's no point in having the "obsolete" token before some tokens, we can just collapse
  # it away.
  defp postprocess_tokens([{:obsolete, line}, {token_name, line, _value} = token | rest])
       when token_name in [:comment, :str_lines] do
    [token | postprocess_tokens(rest)]
  end

  defp postprocess_tokens([token | rest]) do
    [token | postprocess_tokens(rest)]
  end

  defp postprocess_tokens([]) do
    []
  end

  # End of file.
  defp tokenize_line(<<>>, line, _strip_meta?, acc) do
    {:ok, [{:"$end", line} | acc] |> Enum.reverse() |> postprocess_tokens()}
  end

  # Go to the next line.
  defp tokenize_line(<<?\n, rest::binary>>, line, strip_meta?, acc) do
    tokenize_line(rest, line + 1, strip_meta?, acc)
  end

  # Skip other whitespace.
  defp tokenize_line(<<char, rest::binary>>, line, strip_meta?, acc)
       when char in @whitespace_no_nl do
    tokenize_line(rest, line, strip_meta?, acc)
  end

  # Skip Meta Information when strip_meta is enabled
  defp tokenize_line(<<?#, rest::binary>>, line, true, acc) do
    from_next_line = discard_until_nl(rest)
    tokenize_line(from_next_line, line, true, acc)
  end

  # Obsolete comment.
  defp tokenize_line(<<"#~", rest::binary>>, line, strip_meta?, acc) do
    tokenize_line(rest, line, strip_meta?, [{:obsolete, line} | acc])
  end

  # Previous comment.
  defp tokenize_line(<<"#|", rest::binary>>, line, strip_meta?, acc) do
    tokenize_line(rest, line, strip_meta?, [{:previous, line} | acc])
  end

  # Normal comment.
  defp tokenize_line(<<?#, _rest::binary>> = rest, line, strip_meta?, acc) do
    {contents, rest} = to_eol_or_eof(rest, "")
    tokenize_line(rest, line, strip_meta?, [{:comment, line, contents} | acc])
  end

  # Keywords.
  for kw <- @string_keywords do
    defp tokenize_line(unquote(kw) <> <<char, rest::binary>>, line, strip_meta?, acc)
         when char in @whitespace do
      acc = [{unquote(String.to_existing_atom(kw)), line} | acc]
      tokenize_line(rest, line, strip_meta?, acc)
    end

    defp tokenize_line(unquote(kw) <> _rest, line, _strip_meta?, _acc) do
      {:error, line, "no space after '#{unquote(kw)}'"}
    end
  end

  # `msgstr`.
  defp tokenize_line("msgstr[" <> <<rest::binary>>, line, strip_meta?, acc) do
    case tokenize_plural_form(rest, "") do
      {:ok, plural_form, rest} ->
        # The order of the :plural_form and :msgstr tokens is inverted since
        # the `acc` array of tokens will be reversed at the end.
        acc = [{:plural_form, line, plural_form}, {:msgstr, line} | acc]
        tokenize_line(rest, line, strip_meta?, acc)

      {:error, reason} ->
        {:error, line, reason}
    end
  end

  defp tokenize_line("msgstr" <> <<char, rest::binary>>, line, strip_meta?, acc)
       when char in @whitespace do
    acc = [{:msgstr, line} | acc]
    tokenize_line(rest, line, strip_meta?, acc)
  end

  defp tokenize_line("msgstr" <> _rest, line, _strip_meta?, _acc) do
    {:error, line, "no space after 'msgstr'"}
  end

  # String.
  defp tokenize_line(<<?", rest::binary>>, line, strip_meta?, acc) do
    case tokenize_string(rest, "") do
      {:ok, string, rest} ->
        tokenize_line(rest, line, strip_meta?, add_str_lines(line, string, acc))

      {:error, reason} ->
        {:error, line, reason}
    end
  end

  # Unknown keyword.
  # At this point, there has to be a syntax error. Here, since the first byte is
  # a letter (we don't take care of unicode or fancy stuff, just ASCII letters),
  # we assume there's an unknown keyword. We parse it with a regex
  # so that the error message is informative.
  defp tokenize_line(<<letter, _rest::binary>> = binary, line, _strip_meta?, _acc)
       when letter in ?a..?z or letter in ?A..?Z do
    next_word = List.first(Regex.run(~r/\w+/u, binary))
    {:error, line, "unknown keyword '#{next_word}'"}
  end

  # Unknown token.
  # Last resort: this is just a plain unexpected token. We take the first
  # Unicode char of the given binary and build an informative error message
  # (with the codepoint of the char).
  defp tokenize_line(binary, line, _strip_meta?, _acc) when is_binary(binary) do
    # To get the first Unicode char, we convert to char list first.
    [char | _] = String.to_charlist(binary)
    msg = :io_lib.format(~c"unexpected token: \"~ts\" (codepoint U+~4.16.0B)", [[char], char])
    {:error, line, :unicode.characters_to_binary(msg)}
  end

  defp discard_until_nl(content)
  defp discard_until_nl(<<?\n, _rest::binary>> = content), do: content
  defp discard_until_nl(<<>>), do: <<>>
  defp discard_until_nl(<<_char, rest::binary>>), do: discard_until_nl(rest)

  @obsolete_keywords ~w(msgid msgid_plural msgctxt msgstr)a

  # Collapse the string into the previous str_lines token if there is one *on the same line*.
  defp add_str_lines(line, string, [{:str_lines, line, strings} | acc]) do
    [{:str_lines, line, [string | strings]} | acc]
  end

  defp add_str_lines(_line, string, [
         {:str_lines, line, strings},
         {keyword, _keyword_line} = keyword_token | acc
       ])
       when keyword in @obsolete_keywords do
    [{:str_lines, line, [string | strings]}, keyword_token | acc]
  end

  # Same as the previous clause, but here we collapse for plural forms.
  defp add_str_lines(_line, string, [
         {:str_lines, line, strings},
         {:plural_form, _plural_form_line, _plural_form} = plural_form_token,
         {:msgstr, _keyword_line} = keyword_token | acc
       ]) do
    [
      {:str_lines, line, [string | strings]},
      plural_form_token,
      keyword_token | acc
    ]
  end

  # If this str_lines token comes after a "modifier" comment (#| or #~), then
  # we collapse into the previous str_lines token to avoid tokens like:
  # obsolete str_lines obsolete str_lines obsolete str_lines ...
  defp add_str_lines(_line, string, [
         {modifier, _new_modifier_line},
         {:str_lines, line, strings},
         {keyword, _keyword_line} = keyword_token,
         {modifier, _old_modifier_line} = modifier_token | acc
       ])
       when modifier in [:obsolete, :previous] and keyword in @obsolete_keywords do
    [{:str_lines, line, [string | strings]}, keyword_token, modifier_token | acc]
  end

  # Same as the previous clause, but here we collapse for plural forms.
  defp add_str_lines(_line, string, [
         {modifier, _new_modifier_line},
         {:str_lines, line, strings},
         {:plural_form, _plural_form_line, _plural_form} = plural_form_token,
         {:msgstr, _keyword_line} = keyword_token,
         {modifier, _old_modifier_line} = modifier_token | acc
       ])
       when modifier in [:obsolete, :previous] do
    [
      {:str_lines, line, [string | strings]},
      plural_form_token,
      keyword_token,
      modifier_token | acc
    ]
  end

  # There was no str_lines token, so we add a new one.
  defp add_str_lines(line, string, acc) do
    [{:str_lines, line, [string]} | acc]
  end

  # Parses the double-quotes-delimited string `str` into a single string. Note
  # that `str` doesn't start with a double quote (since that was needed to
  # identify the start of a string). Note that the rest of the original string
  # doesn't include the closing double quote.
  defp tokenize_string(str, acc)

  defp tokenize_string(<<?", rest::binary>>, acc), do: {:ok, acc, rest}

  defp tokenize_string(<<?\\, char, rest::binary>>, acc)
       when char in @escapable_chars,
       do: tokenize_string(rest, <<acc::binary, escape_char(char)>>)

  defp tokenize_string(<<?\\, _char, _rest::binary>>, _acc),
    do: {:error, "unsupported escape code"}

  defp tokenize_string(<<?\n, _rest::binary>>, _acc), do: {:error, "newline in string"}

  defp tokenize_string(<<char, rest::binary>>, acc),
    do: tokenize_string(rest, <<acc::binary, char>>)

  defp tokenize_string(<<>>, _acc), do: {:error, "missing token \""}

  defp tokenize_plural_form(<<digit, rest::binary>>, acc) when digit in ~c"0123456789" do
    tokenize_plural_form(rest, <<acc::binary, digit>>)
  end

  defp tokenize_plural_form(<<?], char, rest::binary>>, acc)
       when char in @whitespace and acc != <<>> do
    {:ok, String.to_integer(acc), rest}
  end

  defp tokenize_plural_form(<<?], _rest::binary>>, acc) when acc != <<>> do
    {:error, "missing space after 'msgstr[#{acc}]'"}
  end

  defp tokenize_plural_form(_binary, _acc) do
    {:error, "invalid plural form"}
  end

  defp escape_char(?n), do: ?\n
  defp escape_char(?t), do: ?\t
  defp escape_char(?r), do: ?\r
  defp escape_char(?"), do: ?"
  defp escape_char(?\\), do: ?\\

  defp to_eol_or_eof(<<?\n, _rest::binary>> = rest, acc), do: {acc, rest}
  defp to_eol_or_eof(<<>>, acc), do: {acc, ""}
  defp to_eol_or_eof(<<char, rest::binary>>, acc), do: to_eol_or_eof(rest, <<acc::binary, char>>)
end
