defmodule Expo.PO do
  @moduledoc """
  File handling for PO (`.po`) and POT (`.pot`) files.
  """

  alias Expo.Messages
  alias Expo.PO.{DuplicateMessagesError, Parser, SyntaxError}

  @typedoc """
  Parsing option.

    * `:file` (`t:Path.t/0`) - path to use in error messages when using `parse_string/2`. If not present, errors
      don't have a path.

    * `:strip_meta` (`t:boolean/0`) - include only messages (no comments and other metadata) from the `.po` file
    to reduce memory usage when meta information is not needed.
    Defaults to `false`.
  """
  @type parse_option :: {:file, Path.t()} | {:strip_meta, boolean()}

  @doc """
  Dumps a `Expo.Messages` struct as iodata.

  This function dumps a `Expo.Messages` struct (representing a PO file) as iodata,
  which can later be written to a file or converted to a string with
  `IO.iodata_to_binary/1`.

  ## Examples

  After running the following code:

      iodata =
        Expo.PO.compose(%Expo.Messages{
          headers: ["Last-Translator: Jane Doe"],
          messages: [
            %Expo.Message.Singular{msgid: ["foo"], msgstr: ["bar"], comments: "A comment"}
          ]
        })

      File.write!("/tmp/test.po", iodata)

  the `/tmp/test.po` file would look like this:

      msgid ""
      msgstr ""
      "Last-Translator: Jane Doe"

      # A comment
      msgid "foo"
      msgstr "bar"

  """
  @spec compose(Messages.t()) :: iodata()
  defdelegate compose(messages), to: Expo.PO.Composer

  @doc """
  Parses the given `string` into a `Expo.Messages` struct.

  It returns `{:ok, messages}` if there are no errors, otherwise
  `{:error, error}` where `error` is an exception struct.

  ## Examples

      iex> {:ok, po} = Expo.PO.parse_string(\"""
      ...> msgid "foo"
      ...> msgstr "bar"
      ...> \""")
      iex> [message] = po.messages
      iex> message.msgid
      ["foo"]
      iex> message.msgstr
      ["bar"]
      iex> po.headers
      []

      iex> Expo.PO.parse_string("foo")
      {:error, %Expo.PO.SyntaxError{line: 1, reason: "unknown keyword 'foo'"}}

  """
  @spec parse_string(String.t(), [parse_option()]) ::
          {:ok, Messages.t()} | {:error, SyntaxError.t() | DuplicateMessagesError.t()}
  def parse_string(string, options \\ []) when is_binary(string) and is_list(options) do
    Parser.parse(string, options)
  end

  @doc """
  Parses `string` into a `Expo.Messages` struct, raising an exception if there are
  any errors.

  Works exactly like `parse_string/1`, but returns a `Expo.Messages` struct
  if there are no errors or raises an exception if there are.

  ## Examples

      iex> po = Expo.PO.parse_string!(\"""
      ...> msgid "foo"
      ...> msgstr "bar"
      ...> \""")
      iex> [message] = po.messages
      iex> message.msgid
      ["foo"]
      iex> message.msgstr
      ["bar"]
      iex> po.headers
      []

      iex> Expo.PO.parse_string!("msgid")
      ** (Expo.PO.SyntaxError) 1: no space after 'msgid'

  """
  @spec parse_string!(String.t(), [parse_option()]) :: Messages.t()
  def parse_string!(string, opts \\ []) do
    case parse_string(string, opts) do
      {:ok, parsed} -> parsed
      {:error, error} -> raise error
    end
  end

  @doc """
  Parses the contents of a file into a `Expo.Messages` struct.

  This function works similarly to `parse_string/1` except that it takes a file
  and parses the contents of that file. It can return:

    * `{:ok, po}` if the parsing is successful

    * `{:error, error}` if there is an error with the contents of the
      `.po` file (for example, a syntax error); `error` is an exception struct

    * `{:error, reason}` if there is an error with reading the file (this error
      is one of the errors that can be returned by `File.read/1`)

  ## Examples

      {:ok, po} = Expo.PO.parse_file("messages.po")
      po.file
      #=> "messages.po"

      Expo.PO.parse_file("nonexistent")
      #=> {:error, :enoent}

  """
  @spec parse_file(Path.t(), [parse_option()]) ::
          {:ok, Messages.t()}
          | {:error, SyntaxError.t() | DuplicateMessagesError.t() | File.posix()}
  def parse_file(path, options \\ []) when is_list(options) do
    with {:ok, contents} <- File.read(path) do
      parse_string(contents, Keyword.put_new(options, :file, path))
    end
  end

  @doc """
  Parses the contents of a file into a `Expo.Messages` struct, raising if there
  are any errors.

  Works like `parse_file/1`, except that it raises an exception
  if there are issues with the contents of the file or with reading the file.

  ## Examples

      Expo.PO.parse_file!("nonexistent.po")
      #=> ** (File.Error) could not parse "nonexistent.po": no such file or directory

  """
  @spec parse_file!(Path.t(), [parse_option()]) :: Messages.t()
  def parse_file!(path, opts \\ []) do
    case parse_file(path, opts) do
      {:ok, parsed} ->
        parsed

      {:error, %mod{} = error} when mod in [SyntaxError, DuplicateMessagesError] ->
        raise error

      {:error, reason} ->
        raise File.Error, reason: reason, action: "parse", path: Keyword.get(opts, :file, path)
    end
  end
end
