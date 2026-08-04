defmodule Expo.Util do
  @moduledoc false

  alias Expo.Message

  @spec extract_meta_headers([Message.t()]) :: {[String.t()], [[String.t()]], [Message.t()]}
  def extract_meta_headers(messages)

  def extract_meta_headers([
        %Message.Singular{msgid: [""], msgstr: msgstr, comments: comments} | messages
      ]),
      do: {msgstr, comments, messages}

  def extract_meta_headers(messages), do: {[], [], messages}

  @spec inject_meta_headers([String.t()], [[String.t()]], [Message.t()]) :: [Message.t()]
  def inject_meta_headers(headers, comments, messages)
  def inject_meta_headers([], [], messages), do: messages

  def inject_meta_headers([], comments, messages) do
    inject_meta_headers([""], comments, messages)
  end

  def inject_meta_headers(headers, comments, messages) do
    [
      %Message.Singular{msgid: [""], msgstr: headers, comments: comments}
      | messages
    ]
  end

  @spec rebalance_strings(iodata()) :: iodata()
  def rebalance_strings(strings) do
    strings |> IO.iodata_to_binary() |> split_at_newline()
  end

  defp split_at_newline(subject, acc_string \\ "", acc_list \\ [])
  defp split_at_newline(<<>>, acc_string, acc_list), do: Enum.reverse([acc_string | acc_list])

  defp split_at_newline(<<?\n, rest::binary>>, acc_string, acc_list),
    do: split_at_newline(rest, "", [acc_string <> "\n" | acc_list])

  defp split_at_newline(<<character::utf8, rest::binary>>, acc_string, acc_list),
    do: split_at_newline(rest, <<acc_string::binary, character::utf8>>, acc_list)
end
