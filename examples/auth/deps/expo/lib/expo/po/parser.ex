defmodule Expo.PO.Parser do
  @moduledoc false

  alias Expo.{Message, Messages, PO, Util}
  alias Expo.PO.{DuplicateMessagesError, SyntaxError, Tokenizer}

  @bom <<0xEF, 0xBB, 0xBF>>

  @spec parse(binary(), [PO.parse_option()]) ::
          {:ok, Messages.t()}
          | {:error, SyntaxError.t() | DuplicateMessagesError.t()}
  def parse(content, opts) do
    content = prune_bom(content, Keyword.get(opts, :file, "nofile"))

    with {:ok, tokens} <- tokenize(content, opts),
         {:ok, po} <- parse_tokens(tokens),
         {:ok, po} <- check_for_duplicates(po) do
      {:ok, %Messages{po | file: Keyword.get(opts, :file)}}
    else
      {:error, %mod{} = error} when mod in [SyntaxError, DuplicateMessagesError] ->
        {:error, %{error | file: opts[:file]}}
    end
  end

  defp tokenize(content, opts) do
    case Tokenizer.tokenize(content, opts) do
      {:ok, tokens} -> {:ok, tokens}
      {:error, line, message} -> {:error, %SyntaxError{line: line, reason: message}}
    end
  end

  defp parse_tokens(tokens) when is_list(tokens) do
    with {:ok, po_entries} <- :expo_po_parser.parse(tokens),
         {:ok, top_comments, headers, messages} <- parse_yecc_result(po_entries) do
      {:ok,
       %Messages{
         headers: headers,
         messages: messages,
         top_comments: top_comments
       }}
    else
      {:error, _reason} = error -> parse_error(error)
    end
  end

  defp parse_yecc_result(po_entries)
  defp parse_yecc_result(:empty), do: {:ok, [], [], []}
  defp parse_yecc_result({:only_comments, comments}), do: {:ok, comments, [], []}

  defp parse_yecc_result({:messages, messages}) do
    unpacked_messages = Enum.map(messages, &unpack_comments/1)

    {headers, top_comments, messages} = Util.extract_meta_headers(unpacked_messages)
    {:ok, top_comments, headers, messages}
  end

  defp unpack_comments(message) do
    message
    |> extract_comments()
    |> extract_references()
    |> extract_extracted_comments()
    |> extract_flags()
  end

  defp parse_error({:error, {line, _module, reason}}) do
    {:error, %SyntaxError{line: line, reason: parse_error_reason(reason)}}
  end

  defp extract_comments(%_struct{comments: comments} = message) do
    %{message | comments: Enum.map(comments, &strip_leading(&1, "#"))}
  end

  defp extract_references(%_struct{comments: comments} = message) do
    {reference_comments, other_comments} = Enum.split_with(comments, &match?(":" <> _rest, &1))

    references =
      reference_comments
      |> Enum.reject(fn ":" <> comm -> String.trim(comm) == "" end)
      |> Enum.map(&parse_references/1)

    %{message | references: references, comments: other_comments}
  end

  defp parse_references(":" <> comment) do
    comment
    # Reversing String so that regex lookahead works
    # (negative does not support flexible size lookups)
    |> String.reverse()
    |> String.split(~r/(,|\s(?=\d+:))/, trim: true)
    |> Enum.reverse()
    |> Enum.map(fn reference ->
      reference = reference |> String.reverse() |> String.trim()

      case Regex.scan(~r/^(.+):(\d+)$/, reference) do
        [] -> reference
        [[_file_and_line, file, line]] -> {file, String.to_integer(line)}
      end
    end)
  end

  defp extract_extracted_comments(%_struct{comments: comments} = message) do
    {extracted_comments, other_comments} = Enum.split_with(comments, &match?("." <> _rest, &1))

    %{
      message
      | extracted_comments: Enum.map(extracted_comments, &strip_leading(&1, ".")),
        comments: other_comments
    }
  end

  defp extract_flags(%_struct{comments: comments} = message) do
    {flag_comments, other_comments} = Enum.split_with(comments, &match?("," <> _rest, &1))
    %{message | flags: parse_flags(flag_comments), comments: other_comments}
  end

  defp parse_flags(flag_comments) do
    Enum.map(flag_comments, fn "," <> content ->
      content |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end)
  end

  defp check_for_duplicates(messages, existing \\ %{}, duplicates \\ [], keep \\ [])

  defp check_for_duplicates(
         %Messages{messages: [message | messages]} = po,
         existing,
         duplicates,
         keep
       ) do
    key = Message.key(message)
    source_line = Message.source_line_number(message, :msgid)

    {duplicates, keep} =
      case Map.fetch(existing, key) do
        {:ok, old_line} ->
          {[
             build_duplicated_error(message, old_line, source_line)
             | duplicates
           ], keep}

        :error ->
          {duplicates, [message | keep]}
      end

    check_for_duplicates(
      %Messages{po | messages: messages},
      Map.put_new(existing, key, source_line),
      duplicates,
      keep
    )
  end

  defp check_for_duplicates(%Messages{messages: []} = po, _existing, [], keep),
    do: {:ok, %Messages{po | messages: Enum.reverse(keep)}}

  defp check_for_duplicates(%Messages{messages: []} = po, _existing, duplicates, keep),
    do:
      {:error,
       %DuplicateMessagesError{
         duplicates: Enum.reverse(duplicates),
         catalogue: %Messages{po | messages: Enum.reverse(keep)}
       }}

  defp build_duplicated_error(%Message.Singular{} = message, old_line, new_line) do
    id = IO.iodata_to_binary(message.msgid)
    {message, "found duplicate on line #{new_line} for msgid: '#{id}'", new_line, old_line}
  end

  defp build_duplicated_error(%Message.Plural{} = message, old_line, new_line) do
    id = IO.iodata_to_binary(message.msgid)
    idp = IO.iodata_to_binary(message.msgid_plural)

    error_message =
      "found duplicate on line #{new_line} for msgid: '#{id}' and msgid_plural: '#{idp}'"

    {message, error_message, new_line, old_line}
  end

  defp strip_leading(subject, to_strip) do
    true = String.starts_with?(subject, to_strip)

    String.slice(
      subject,
      String.length(to_strip),
      String.length(subject) - String.length(to_strip)
    )
  end

  # We need to explicitly parse the error reason that yecc spits out because a
  # `{type, line, token}` token is printed as the Erlang term in the error (by
  # yecc). So, for example, if a token has a binary value then yecc will return
  # something like:
  #
  #     syntax error before: <<"my token">>
  #
  # which is not what we want, as we want the term to be printed as an Elixir
  # term. While this is ugly, it's necessary (as yecc is not very extensible)
  # and is what Elixir itself does
  # (https://github.com/elixir-lang/elixir/blob/b80651/lib/elixir/src/elixir_errors.erl#L51-L103).
  defp parse_error_reason([error, token]) do
    IO.chardata_to_string(parse_error_reason(error, to_string(token)))
  end

  defp parse_error_reason(~c"syntax error before: " = prefix, "<<" <> rest),
    do: [prefix, binary_part(rest, 0, byte_size(rest) - 2)]

  defp parse_error_reason(~c"syntax error before: " = prefix, "[<<" <> rest),
    do: [prefix, binary_part(rest, 0, byte_size(rest) - 3)]

  defp parse_error_reason(error, token), do: [error, token]

  # This function removes a BOM byte sequence from the start of the given string
  # if this sequence is present. A BOM byte sequence
  # (https://en.wikipedia.org/wiki/Byte_order_mark) is a thing that Unicode uses
  # as a kind of metadata for a file; it's placed at the start of the file. GNU
  # Gettext blows up if it finds a BOM sequence at the start of a file (as you
  # can check with the `msgfmt` program); here, we don't blow up but we print a
  # warning saying the BOM is present and suggesting to remove it.
  #
  # Note that `file` is used to give a nicer warning in case the BOM is
  # present. This function is in fact called by both parse_string/1 and
  # parse_file/1. Since parse_file/1 relies on parse_string/1, in case
  # parse_file/1 is called this function is called twice but that's ok because
  # in case of BOM, parse_file/1 will remove it first and parse_string/1 won't
  # issue the warning again as its call to prune_bom/2 will be a no-op.
  defp prune_bom(str, file)

  defp prune_bom(@bom <> str, file) do
    file_or_string = if file == "nofile", do: "string", else: "file"

    warning =
      "#{file}: warning: the #{file_or_string} being parsed starts " <>
        "with a BOM byte sequence (#{inspect(@bom, binaries: :as_binaries)}). " <>
        "These bytes are ignored by Gettext but it's recommended to remove " <>
        "them. To know more about BOM, read https://en.wikipedia.org/wiki/Byte_order_mark."

    IO.puts(:stderr, warning)

    str
  end

  defp prune_bom(str, _file) when is_binary(str) do
    str
  end
end
