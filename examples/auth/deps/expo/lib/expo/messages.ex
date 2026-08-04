defmodule Expo.Messages do
  @moduledoc """
  A struct that represents lists of `Expo.Message.Singular` and `Expo.Message.Plural`
  structs for MO and PO files.

  All fields in the struct are public. See [`%Expo.Messages{}`](`__struct__/0`).
  """

  alias Expo.{Message, Util}

  @typedoc """
  The type for this struct.
  """
  @type t :: %__MODULE__{
          headers: [String.t()],
          top_comments: [[String.t()]],
          messages: [Message.t()],
          file: nil | Path.t()
        }

  @doc """
  The struct to represent a list of messages.

  For the type of each field, see `t:t/0`.
  """
  @enforce_keys [:messages]
  defstruct headers: [], messages: [], top_comments: [], file: nil

  @doc """
  Re-balances all strings.

  This function does the following things:

    * Re-balances all headers (see `Expo.Message.Singular.rebalance/1` and
      `Expo.Message.Plural.rebalance/1`)

    * Puts one string per newline of `headers` and add one empty line at start

  ### Examples

      iex> Expo.Messages.rebalance(%Expo.Messages{
      ...>   headers: ["", "hello", "\\n", "", "world", ""],
      ...>   messages: [%Expo.Message.Singular{
      ...>     msgid: ["", "hello", "\\n", "", "world", ""],
      ...>     msgstr: ["", "hello", "\\n", "", "world", ""]
      ...>   }]
      ...> })
      %Expo.Messages{
        headers: ["", "hello\\n", "world"],
        messages: [%Expo.Message.Singular{
          msgid: ["hello\\n", "world"],
          msgstr: ["hello\\n", "world"]
        }]
      }

  """
  @spec rebalance(t()) :: t()
  def rebalance(
        %__MODULE__{headers: headers, messages: all_messages, top_comments: top_comments} =
          messages
      ) do
    {headers, top_comments, all_messages} =
      headers
      |> Util.inject_meta_headers(top_comments, all_messages)
      |> Enum.map(fn %struct{} = message -> struct.rebalance(message) end)
      |> Util.extract_meta_headers()

    headers =
      case headers do
        [] -> []
        headers -> ["" | headers]
      end

    %__MODULE__{
      messages
      | headers: headers,
        top_comments: top_comments,
        messages: all_messages
    }
  end

  @doc """
  Gets a header by name.

  The name of the header is case-insensitive.

  ### Examples

      iex> messages = %Expo.Messages{headers: ["Language: en_US\\n"], messages: []}
      iex> Expo.Messages.get_header(messages, "language")
      ["en_US"]

      iex> messages = %Expo.Messages{headers: ["Language: en_US\\n"], messages: []}
      iex> Expo.Messages.get_header(messages, "invalid")
      []

  """
  @spec get_header(t(), String.t()) :: [String.t()]
  def get_header(%__MODULE__{headers: headers}, header_name) when is_binary(header_name) do
    header_name_match = Regex.escape(header_name)
    escaped_newline = Regex.escape("\\\n")

    ~r/
      # Start of line
      ^
      # Header Name
      (?<header>
        #{header_name_match}
      ):
      # Ignore Whitespace
      \s
      (?<content>
        (
          # Allow an escaped newline in content
          #{escaped_newline}
          |
          # Allow everything except a newline in content
          [^\n]
        )*
      )
      # Header must end with newline or end of string
      (\n|\z)
    /imx
    |> Regex.scan(IO.iodata_to_binary(headers), capture: ["content"])
    |> Enum.map(fn [content] -> content end)
  end

  @doc """
  Finds a given `message_to_find` in a list of `messages`.

  Equality between messages is checked using `Expo.Message.same?/2`.

  Returns `nil` if `message_to_find` is not found.
  """
  @spec find([Message.t()] | t(), Message.t()) :: Message.t() | nil
  def find(%__MODULE__{messages: messages} = _messages, message_to_find) do
    Enum.find(messages, &Message.same?(&1, message_to_find))
  end
end
