defmodule Gettext.Fuzzy do
  @moduledoc false

  alias Expo.Message

  @type message_key :: {binary | nil, binary | {binary, binary}}

  @doc """
  Returns a matcher function that takes two message keys and checks if they
  match.

  `String.jaro_distance/2` (which calculates the Jaro distance) is used to
  measure the distance between the two messages. `threshold` is the minimum
  distance that means a match. `{:match, distance}` is returned in case of a
  match, `:nomatch` otherwise.
  """
  @spec matcher(float) :: (message_key, message_key -> {:match, float} | :nomatch)
  def matcher(threshold) do
    fn old_key, new_key ->
      distance = jaro_distance(old_key, new_key)
      if distance >= threshold, do: {:match, distance}, else: :nomatch
    end
  end

  @doc """
  Finds the Jaro distance between the msgids of two messages.

  To mimic the behaviour of the `msgmerge` tool, this function only calculates
  the Jaro distance of the msgids of the two messages, even if one (or both)
  of them is a plural message.

  As per `msgmerge`, the msgctxt of a message is completely ignored when
  calculating the distance.
  """
  @spec jaro_distance(message_key, message_key) :: float
  def jaro_distance({_context1, key1}, {_context2, key2}) do
    jaro_distance_on_key(key1, key2)
  end

  # Apparently, msgmerge only looks at the msgid when performing fuzzy
  # matching. This means that if we have two plural messages with similar
  # msgids but very different msgid_plurals, they'll still fuzzy match.
  def jaro_distance_on_key(key1, key2) when is_binary(key1) and is_binary(key2),
    do: String.jaro_distance(key1, key2)

  def jaro_distance_on_key({key1, _}, key2) when is_binary(key2),
    do: String.jaro_distance(key1, key2)

  def jaro_distance_on_key(key1, {key2, _}) when is_binary(key1),
    do: String.jaro_distance(key1, key2)

  def jaro_distance_on_key({key1, _}, {key2, _}), do: String.jaro_distance(key1, key2)

  @doc """
  Merges a message with the corresponding fuzzy match.

  `new` is the newest message and `existing` is the existing message
  that we use to populate the msgstr of the newest message.

  Note that if `new` is a regular message, then the result will be a regular
  message; if `new` is a plural message, then the result will be a
  plural message.
  """
  @spec merge(new :: Message.t(), existing :: Message.t()) :: Message.t()
  def merge(new, existing) do
    # Everything comes from "new", except for the msgstr and the comments.
    new
    |> Map.put(:comments, existing.comments)
    |> merge_msgstr(existing)
    |> Message.append_flag("fuzzy")
  end

  defp merge_msgstr(%Message.Singular{} = new, %Message.Singular{} = existing),
    do: %{new | msgstr: existing.msgstr}

  defp merge_msgstr(%Message.Singular{} = new, %Message.Plural{} = existing),
    do: %{new | msgstr: existing.msgstr[0]}

  defp merge_msgstr(%Message.Plural{} = new, %Message.Singular{} = existing),
    do: %{new | msgstr: Map.new(new.msgstr, fn {i, _} -> {i, existing.msgstr} end)}

  defp merge_msgstr(%Message.Plural{} = new, %Message.Plural{} = existing),
    do: %{new | msgstr: existing.msgstr}
end
