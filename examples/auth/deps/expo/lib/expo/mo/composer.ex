defmodule Expo.MO.Composer do
  @moduledoc false

  alias Expo.Message
  alias Expo.Messages
  alias Expo.MO
  alias Expo.Util

  @spec compose(Messages.t(), [MO.compose_option()]) :: iodata()
  def compose(messages, opts) do
    messages =
      Util.inject_meta_headers(
        messages.headers,
        messages.top_comments,
        messages.messages
      )

    endianness = Keyword.get(opts, :endianness, :little)
    messages = Enum.reject(messages, & &1.obsolete)

    messages =
      if Keyword.get(opts, :use_fuzzy, false) do
        messages
      else
        Enum.reject(messages, fn %_struct{flags: flags} ->
          flags
          |> List.flatten()
          |> Enum.member?("fuzzy")
        end)
      end

    if Keyword.get(opts, :statistics, false) do
      send(self(), {MO, :message_count, length(messages)})
    end

    number_of_messages = length(messages)
    header_length = 28
    offset_of_table_with_original_strings = header_length

    offset_of_table_with_message_strings =
      offset_of_table_with_original_strings + number_of_messages * 4 * 2

    size_of_hashing_table = 0

    offset_of_hashing_table = offset_of_table_with_message_strings + number_of_messages * 4 * 2

    offset_of_original_string_data = offset_of_hashing_table + size_of_hashing_table

    out =
      header(
        endianness,
        number_of_messages,
        offset_of_table_with_original_strings,
        offset_of_table_with_message_strings,
        size_of_hashing_table,
        offset_of_hashing_table
      )

    {original_string_positions, original_strings, offset_of_message_string_data} =
      string_table(
        endianness,
        messages,
        fn
          %Message.Singular{msgctxt: nil, msgid: msgid} ->
            [msgid]

          %Message.Singular{msgctxt: msgctxt, msgid: msgid} ->
            [msgctxt, 4, msgid]

          %Message.Plural{msgctxt: nil, msgid: msgid, msgid_plural: msgid_plural} ->
            [msgid, 0, msgid_plural]

          %Message.Plural{msgctxt: msgctxt, msgid: msgid, msgid_plural: msgid_plural} ->
            [msgctxt, 4, msgid, 0, msgid_plural]
        end,
        offset_of_original_string_data
      )

    out = [out | original_string_positions]

    {translated_string_positions, translated_strings, _end_offset} =
      string_table(
        endianness,
        messages,
        fn
          %Message.Singular{msgstr: msgstr} -> [msgstr]
          %Message.Plural{msgstr: msgstr} -> msgstr |> Map.values() |> Enum.intersperse(0)
        end,
        offset_of_message_string_data
      )

    [out | [translated_string_positions, original_strings, translated_strings]]
  end

  defp header(
         endianness,
         number_of_strings,
         offset_of_table_with_original_strings,
         offset_of_table_with_message_strings,
         size_of_hashing_table,
         offset_of_hashing_table
       )

  defp header(
         :little,
         number_of_strings,
         offset_of_table_with_original_strings,
         offset_of_table_with_message_strings,
         size_of_hashing_table,
         offset_of_hashing_table
       ),
       do:
         <<0xDE120495::size(4)-unit(8), 0::little-unsigned-integer-size(2)-unit(8),
           0::little-unsigned-integer-size(2)-unit(8),
           number_of_strings::little-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_original_strings::little-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_message_strings::little-unsigned-integer-size(4)-unit(8),
           size_of_hashing_table::little-unsigned-integer-size(4)-unit(8),
           offset_of_hashing_table::little-unsigned-integer-size(4)-unit(8)>>

  defp header(
         :big,
         number_of_strings,
         offset_of_table_with_original_strings,
         offset_of_table_with_message_strings,
         size_of_hashing_table,
         offset_of_hashing_table
       ),
       do:
         <<0x950412DE::size(4)-unit(8), 0::big-unsigned-integer-size(2)-unit(8),
           0::big-unsigned-integer-size(2)-unit(8),
           number_of_strings::big-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_original_strings::big-unsigned-integer-size(4)-unit(8),
           offset_of_table_with_message_strings::big-unsigned-integer-size(4)-unit(8),
           size_of_hashing_table::big-unsigned-integer-size(4)-unit(8),
           offset_of_hashing_table::big-unsigned-integer-size(4)-unit(8)>>

  defp string_table(
         endianness,
         messages,
         content_callback,
         acc_offset,
         acc_table \\ [],
         acc_data \\ []
       )

  defp string_table(endianness, [head | tail], content_callback, acc_offset, acc_table, acc_data) do
    content = content_callback.(head)
    cell_length = byte_size(IO.iodata_to_binary(content))
    {table_entry, acc_offset} = table_entry(endianness, acc_offset, cell_length)

    string_table(
      endianness,
      tail,
      content_callback,
      acc_offset + 1,
      [acc_table | [table_entry]],
      [acc_data | [content, <<0>>]]
    )
  end

  defp string_table(_endianness, [], _content_callback, acc_offset, acc_table, acc_data),
    do: {acc_table, acc_data, acc_offset}

  defp table_entry(:little, cell_offset, cell_length) do
    {<<cell_length::little-unsigned-integer-size(4)-unit(8),
       cell_offset::little-unsigned-integer-size(4)-unit(8)>>, cell_offset + cell_length}
  end

  defp table_entry(:big, cell_offset, cell_length) do
    {<<cell_length::big-unsigned-integer-size(4)-unit(8),
       cell_offset::big-unsigned-integer-size(4)-unit(8)>>, cell_offset + cell_length}
  end
end
