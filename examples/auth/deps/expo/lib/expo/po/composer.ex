defmodule Expo.PO.Composer do
  @moduledoc false

  alias Expo.Message
  alias Expo.Messages
  alias Expo.Util

  @spec compose(Messages.t()) :: iodata()
  def compose(%Messages{
        headers: headers,
        top_comments: top_comments,
        messages: messages
      }) do
    headers
    |> Util.inject_meta_headers(top_comments, messages)
    |> dump_messages()
  end

  defp dump_messages(messages) do
    messages
    |> Enum.map(&dump_message(&1))
    |> Enum.intersperse(?\n)
  end

  defp dump_message(%Message.Singular{obsolete: obsolete} = t) do
    line_prefix = if(obsolete, do: "#~ ", else: [])

    [
      dump_comments(t.comments, line_prefix),
      dump_extracted_comments(t.extracted_comments, line_prefix),
      dump_references(t.references, line_prefix),
      dump_flags(t.flags, line_prefix),
      dump_previous_messages(t.previous_messages, line_prefix),
      dump_msgctxt(t.msgctxt, line_prefix),
      dump_kw_and_strings("msgid", t.msgid, line_prefix),
      dump_kw_and_strings("msgstr", t.msgstr, line_prefix)
    ]
  end

  defp dump_message(%Message.Plural{obsolete: obsolete} = t) do
    line_prefix = if(obsolete, do: "#~ ", else: [])

    [
      dump_comments(t.comments, line_prefix),
      dump_extracted_comments(t.extracted_comments, line_prefix),
      dump_references(t.references, line_prefix),
      dump_flags(t.flags, line_prefix),
      dump_previous_messages(t.previous_messages, line_prefix),
      dump_msgctxt(t.msgctxt, line_prefix),
      dump_kw_and_strings("msgid", t.msgid, line_prefix),
      dump_kw_and_strings("msgid_plural", t.msgid_plural, line_prefix),
      dump_plural_msgstr(t.msgstr, line_prefix)
    ]
  end

  defp dump_comments(comments, line_prefix), do: Enum.map(comments, &[line_prefix, "#", &1, ?\n])

  defp dump_extracted_comments(comments, line_prefix),
    do: Enum.map(comments, &[line_prefix, "#.", &1, ?\n])

  defp dump_references(references, line_prefix) do
    Enum.map(references, fn reference_line ->
      [
        line_prefix,
        "#: ",
        reference_line |> Enum.map(&dump_reference_file/1) |> Enum.join(", "),
        ?\n
      ]
    end)
  end

  defp dump_reference_file(reference)
  defp dump_reference_file({file, line}), do: "#{file}:#{line}"
  defp dump_reference_file(file), do: file

  defp dump_flags(flags, line_prefix) do
    Enum.map(flags, fn flag_line ->
      [line_prefix, "#, ", Enum.intersperse(flag_line, ", "), ?\n]
    end)
  end

  defp dump_plural_msgstr(msgstr, obsolete) do
    Enum.map(msgstr, fn {plural_form, str} ->
      dump_kw_and_strings("msgstr[#{plural_form}]", str, obsolete)
    end)
  end

  defp dump_kw_and_strings(keyword, [first | rest], line_prefix) do
    first = [
      line_prefix,
      keyword,
      " ",
      ?",
      escape(first),
      ?",
      ?\n
    ]

    rest = Enum.map(rest, &[line_prefix, ?", escape(&1), ?", ?\n])
    [first | rest]
  end

  defp dump_msgctxt(nil, _line_prefix), do: []

  defp dump_msgctxt(string, line_prefix), do: dump_kw_and_strings("msgctxt", string, line_prefix)

  defp dump_previous_messages(messages, line_prefix) do
    Enum.map(messages, fn
      %Message.Singular{msgid: msgid, obsolete: obsolete} ->
        dump_previous_msgids(msgid, obsolete, line_prefix)

      %Message.Plural{msgid: msgid, msgid_plural: msgid_plural, obsolete: obsolete} ->
        [
          dump_previous_msgids(msgid, obsolete, line_prefix),
          dump_previous_msgids(msgid_plural, obsolete, "msgid_plural", line_prefix)
        ]
    end)
  end

  defp dump_previous_msgids(previous_msgids, obsolete, keyword \\ "msgid", line_prefix) do
    Enum.map(
      previous_msgids,
      &dump_kw_and_strings(keyword, [IO.iodata_to_binary(&1)], [
        line_prefix,
        if(obsolete, do: "#~| ", else: "#| ")
      ])
    )
  end

  defp escape(str) do
    for <<char <- str>>, into: "", do: escape_char(char)
  end

  defp escape_char(?"), do: ~S(\")
  defp escape_char(?\n), do: ~S(\n)
  defp escape_char(?\t), do: ~S(\t)
  defp escape_char(?\r), do: ~S(\r)
  defp escape_char(?\\), do: <<?\\::utf8, ?\\::utf8>>
  defp escape_char(char), do: <<char>>
end
