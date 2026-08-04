defmodule Expo.MO.Parser do
  @moduledoc false

  alias Expo.{Message, Messages, MO, Util}
  alias Expo.MO.{InvalidFileError, UnsupportedVersionError}

  @spec parse(binary(), [MO.parse_option()]) ::
          {:ok, Messages.t()} | {:error, InvalidFileError.t() | UnsupportedVersionError.t()}
  def parse(content, opts)

  def parse(content, opts) when byte_size(content) >= 28 do
    file = opts[:file]

    with {:ok, {endianness, header}} <- parse_header(binary_part(content, 0, 28)),
         :ok <- check_version(header) do
      messages = parse_messages(endianness, header, content)
      {headers, top_comments, messages} = Util.extract_meta_headers(messages)

      {:ok,
       %Messages{
         messages: messages,
         headers: headers,
         top_comments: top_comments,
         file: file
       }}
    else
      {:error, %mod{} = error} when mod in [InvalidFileError, UnsupportedVersionError] ->
        {:error, %{error | file: file}}
    end
  end

  def parse(_content, opts), do: {:error, %InvalidFileError{file: opts[:file]}}

  ## Helpers

  defp parse_header(
         <<0xDE120495::size(4)-unit(8),
           file_format_revision_major::little-unsigned-integer-size(2)-unit(8),
           file_format_revision_minor::little-unsigned-integer-size(2)-unit(8),
           number_of_strings::little-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_original_strings::little-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_message_strings::little-unsigned-integer-size(4)-unit(8),
           _size_of_hashing_table::little-unsigned-integer-size(4)-unit(8),
           _offset_of_hashing_table::little-unsigned-integer-size(4)-unit(8)>>
       ) do
    {:ok,
     {:little,
      %{
        file_format_revision_major: file_format_revision_major,
        file_format_revision_minor: file_format_revision_minor,
        number_of_strings: number_of_strings,
        offset_of_table_with_original_strings: offset_of_table_with_original_strings,
        offset_of_table_with_message_strings: offset_of_table_with_message_strings
      }}}
  end

  defp parse_header(
         <<0x950412DE::size(4)-unit(8),
           file_format_revision_major::big-unsigned-integer-size(2)-unit(8),
           file_format_revision_minor::big-unsigned-integer-size(2)-unit(8),
           number_of_strings::big-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_original_strings::big-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_message_strings::big-unsigned-integer-size(4)-unit(8),
           _size_of_hashing_table::big-unsigned-integer-size(4)-unit(8),
           _offset_of_hashing_table::big-unsigned-integer-size(4)-unit(8)>>
       ) do
    {:ok,
     {:big,
      %{
        file_format_revision_major: file_format_revision_major,
        file_format_revision_minor: file_format_revision_minor,
        number_of_strings: number_of_strings,
        offset_of_table_with_original_strings: offset_of_table_with_original_strings,
        offset_of_table_with_message_strings: offset_of_table_with_message_strings
      }}}
  end

  defp parse_header(_header_binary), do: {:error, %InvalidFileError{}}

  # Not checking minor since they must be BC compatible
  defp check_version(%{file_format_revision_major: 0}), do: :ok

  defp check_version(header) do
    {:error,
     %UnsupportedVersionError{
       major: header.file_format_revision_major,
       minor: header.file_format_revision_minor
     }}
  end

  defp parse_messages(endianness, header, content) do
    [
      header.offset_of_table_with_original_strings,
      header.offset_of_table_with_message_strings
    ]
    |> Enum.map(&read_table(endianness, content, &1, header.number_of_strings))
    |> zip_with(&to_message/1)
  end

  defp read_table(endianness, content, start_offset, number_of_elements) do
    endianness
    |> read_table_headers(binary_part(content, start_offset, number_of_elements * 2 * 4), [])
    |> Enum.map(fn {offset, length} -> _table_cell = binary_part(content, offset, length) end)
  end

  defp read_table_headers(
         :big = _endianness,
         <<
           cell_length::big-unsigned-integer-size(4)-unit(8),
           cell_offset::big-unsigned-integer-size(4)-unit(8),
           rest::binary
         >>,
         acc
       ) do
    read_table_headers(:big, rest, [{cell_offset, cell_length} | acc])
  end

  defp read_table_headers(
         :little = _endianness,
         <<
           cell_length::little-unsigned-integer-size(4)-unit(8),
           cell_offset::little-unsigned-integer-size(4)-unit(8),
           rest::binary
         >>,
         acc
       ) do
    read_table_headers(:little, rest, [{cell_offset, cell_length} | acc])
  end

  defp read_table_headers(_endianness, <<>>, acc) do
    Enum.reverse(acc)
  end

  defp to_message([msgid, msgstr]) do
    {attrs, message_type} = msg_id_to_message_attrs(msgid)

    msgstr =
      case message_type do
        Message.Singular ->
          [msgstr]

        Message.Plural ->
          for {msgstr, index} <- Enum.with_index(String.split(msgstr, <<0>>)),
              into: %{},
              do: {index, [msgstr]}
      end

    struct!(message_type, Map.put(attrs, :msgstr, msgstr))
  end

  defp msg_id_to_message_attrs(msgid) do
    {attrs, msgid} =
      case String.split(msgid, <<4::utf8>>, parts: 2) do
        [msgid] -> {%{}, msgid}
        [msgctxt, msgid] -> {%{msgctxt: msgctxt}, msgid}
      end

    case String.split(msgid, <<0>>, parts: 2) do
      [msgid] ->
        {Map.merge(attrs, %{msgid: [msgid]}), Message.Singular}

      [msgid, msgid_plural] ->
        {Map.merge(attrs, %{msgid: [msgid], msgid_plural: [msgid_plural]}), Message.Plural}
    end
  end

  # TODO: Remove when requiring at least Elixir 1.12
  if function_exported?(Enum, :zip_with, 2) do
    defp zip_with(lists, mapper), do: Enum.zip_with(lists, mapper)
  else
    defp zip_with(lists, mapper),
      do: lists |> Enum.zip() |> Enum.map(fn {left, right} -> mapper.([left, right]) end)
  end
end
