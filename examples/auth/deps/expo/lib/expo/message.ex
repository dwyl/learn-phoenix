defmodule Expo.Message do
  @moduledoc """
  Functions to work on message structs (`Expo.Message.Singular` and `Expo.Message.Plural`).

  A message is a single PO singular or plural message. For example:

      msgid "Hello"
      msgstr ""

  Message structs are used both to represent reference messages (where the `msgstr` is empty)
  in POT files as well as actual translations.
  """

  alias Expo.Message.{Plural, Singular}

  @typedoc """
  A list of strings representing *lines*.

  This type is used for types such as `t:msgid/0`. The list of strings
  represents the message split into multiple lines, as parsed from a PO(T) file.
  """
  @typedoc since: "0.5.0"
  @type split_string() :: [String.t(), ...]

  @typedoc """
  The `msgid` of a message.
  """
  @type msgid :: split_string()

  @typedoc """
  The `msgstr` of a message.
  """
  @type msgstr :: split_string()

  @typedoc """
  The `msgctxt` of a message.
  """
  @type msgctxt :: split_string()

  @typedoc """
  A type for either a singular or a plural message.
  """
  @type t :: Singular.t() | Plural.t()

  @typedoc """
  The key that can be used to identify a message.

  See `key/1`.
  """
  @opaque key :: Singular.key() | Plural.key()

  @doc """
  Returns a "key" that can be used to identify a message.

  This function returns a "key" that can be used to uniquely identify a
  message assuming that no "same" messages exist; for what "same"
  means, look at the documentation for `same?/2`.

  The purpose of this function is to be used in situations where we'd like to
  group or sort messages but where we don't need the whole structs.

  ## Examples

      iex> t1 = %Expo.Message.Singular{msgid: ["foo"]}
      iex> t2 = %Expo.Message.Singular{msgid: ["", "foo"]}
      iex> Expo.Message.key(t1) == Expo.Message.key(t2)
      true

      iex> t1 = %Expo.Message.Singular{msgid: ["foo"]}
      iex> t2 = %Expo.Message.Singular{msgid: ["bar"]}
      iex> Expo.Message.key(t1) == Expo.Message.key(t2)
      false

  """
  @spec key(t()) :: key()
  def key(message)
  def key(%Singular{} = message), do: Singular.key(message)
  def key(%Plural{} = message), do: Plural.key(message)

  @doc """
  Tells whether two messages are the same message according to their
  `msgid`.

  This function returns `true` if `message1` and `message2` are the same
  message, where "the same" means they have the same `msgid` or the same
  `msgid` and `msgid_plural`.

  ## Examples

      iex> t1 = %Expo.Message.Singular{msgid: ["foo"]}
      iex> t2 = %Expo.Message.Singular{msgid: ["", "foo"]}
      iex> Expo.Message.same?(t1, t2)
      true

      iex> t1 = %Expo.Message.Singular{msgid: ["foo"]}
      iex> t2 = %Expo.Message.Singular{msgid: ["bar"]}
      iex> Expo.Message.same?(t1, t2)
      false

  """
  @spec same?(t(), t()) :: boolean
  def same?(message1, message2), do: key(message1) == key(message2)

  @doc """
  Tells whether the given `message` has the given `flag` specified.

  ### Examples

      iex> Expo.Message.has_flag?(%Expo.Message.Singular{msgid: [], flags: [["foo"]]}, "foo")
      true

      iex> Expo.Message.has_flag?(%Expo.Message.Singular{msgid: [], flags: [["foo"]]}, "bar")
      false

  """
  @spec has_flag?(t(), String.t()) :: boolean()
  def has_flag?(%mod{flags: flags} = _message, flag)
      when mod in [Singular, Plural] and is_binary(flag),
      do: raw_has_flag?(flags, flag)

  defp raw_has_flag?(flags, flag) when is_list(flags) when is_binary(flag),
    do: flag in List.flatten(flags)

  @doc """
  Appends the given `flag` to the given `message`.

  Keeps the line formatting intact.

  ### Examples

      iex> message = %Expo.Message.Singular{msgid: [], flags: []}
      iex> Expo.Message.append_flag(message, "foo")
      %Expo.Message.Singular{msgid: [], flags: [["foo"]]}

  """
  @spec append_flag(t(), String.t()) :: t()
  def append_flag(%mod{flags: flags} = message, flag) when mod in [Singular, Plural],
    do: struct!(message, flags: raw_append_flag(flags, flag))

  @doc false
  @spec raw_append_flag([[String.t()]], String.t()) :: [[String.t()]]
  def raw_append_flag(flags, flag) when is_list(flags) when is_binary(flag) do
    if raw_has_flag?(flags, flag) do
      flags
    else
      case flags do
        [] -> [[flag]]
        [flag_line] -> [flag_line ++ [flag]]
        _multiple_lines -> flags ++ [[flag]]
      end
    end
  end

  @doc """
  Get the source line number of the message.

  ## Examples

      iex> %Expo.Messages{messages: [message]} = Expo.PO.parse_string!(\"""
      ...> msgid "foo"
      ...> msgstr "bar"
      ...> \""")
      iex> Expo.Message.source_line_number(message, :msgid)
      1

  """
  @spec source_line_number(Singular.t(), Singular.block(), default) :: non_neg_integer() | default
        when default: term
  @spec source_line_number(Plural.t(), Plural.block(), default) :: non_neg_integer() | default
        when default: term
  def source_line_number(%mod{} = message, block, default \\ nil)
      when mod in [Singular, Plural] do
    mod.source_line_number(message, block, default)
  end

  @doc """
  Merges two messages.

  If both messages are `Expo.Message.Singular`, the result is a singular message.
  If one of the two messages is a `Expo.Message.Plural`, the result is a plural message.
  This is consistent with the behavior of GNU Gettext.

  ## Examples

      iex> msg1 = %Expo.Message.Singular{msgid: ["test"], flags: [["one"]]}
      ...> msg2 = %Expo.Message.Singular{msgid: ["test"], flags: [["one", "two"]]}
      ...> Expo.Message.merge(msg1, msg2)
      %Expo.Message.Singular{msgid: ["test"], flags: [["one", "two"]]}

      iex> msg1 = %Expo.Message.Singular{msgid: ["test"]}
      ...> msg2 = %Expo.Message.Plural{msgid: ["test"], msgid_plural: ["tests"]}
      ...> Expo.Message.merge(msg1, msg2)
      %Expo.Message.Plural{msgid: ["test"], msgid_plural: ["tests"]}

  """
  @doc since: "0.5.0"
  @spec merge(Singular.t(), Singular.t()) :: Singular.t()
  @spec merge(t(), Plural.t()) :: Plural.t()
  @spec merge(Plural.t(), t()) :: Plural.t()
  def merge(message1, message2)

  def merge(%mod{} = msg1, %mod{} = msg2), do: mod.merge(msg1, msg2)
  def merge(%Singular{} = msg1, %Plural{} = msg2), do: Plural.merge(to_plural(msg1), msg2)
  def merge(%Plural{} = msg1, %Singular{} = msg2), do: Plural.merge(msg1, to_plural(msg2))

  defp to_plural(%Singular{msgstr: msgstr} = singular) do
    msgstr = if IO.iodata_length(msgstr) > 0, do: %{0 => msgstr}, else: %{}

    attributes =
      singular
      |> Map.from_struct()
      |> Map.merge(%{msgstr: msgstr, msgid_plural: []})

    struct!(Plural, attributes)
  end
end
