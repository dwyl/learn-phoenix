defmodule Mix.Tasks.Expo.Msguniq do
  @shortdoc "Unifies duplicate translations in message catalog"

  @moduledoc """
  Unifies duplicate translations in the given PO file.

  By default, this task outputs the file on standard output. If you want to
  *overwrite* the given PO file, pass in the `--output` flag.

  *This task is available since v0.5.0.*

  ## Usage

      mix expo.msguniq PO_FILE [--output-file=OUTPUT_FILE]

  ## Options

  * `--output-file` (`-o`) - File to store the output in. `-` for
    standard output. Defaults to `-`.

  """
  @moduledoc since: "0.5.0"

  use Mix.Task

  alias Expo.Message
  alias Expo.Messages
  alias Expo.PO
  alias Expo.PO.DuplicateMessagesError

  @switches [output_file: :string]
  @aliases [o: :output_file]
  @default_options [output_file: "-"]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:expo)
    {opts, argv} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    opts = Keyword.merge(@default_options, opts)

    output =
      case opts[:output_file] do
        "-" -> IO.stream(:stdio, :line)
        file -> File.stream!(file)
      end

    file =
      case argv do
        [] ->
          Mix.raise("""
          mix expo.msguniq failed due to missing po file path argument
          """)

        [_file_one, _file_two | _other_files] ->
          Mix.raise("""
          mix expo.msguniq failed due to multiple po file path arguments
          Only one is currently supported
          """)

        [file] ->
          file
      end

    case PO.parse_file(file) do
      {:ok, _messages} ->
        :ok

      {:error, %DuplicateMessagesError{duplicates: duplicates, catalogue: catalogue}} ->
        po =
          duplicates
          |> Enum.reduce(catalogue, &merge_duplicate/2)
          |> PO.compose()
          |> Enum.map(&List.wrap/1)

        _output = Enum.into(po, output)

        IO.puts(:stderr, IO.ANSI.format("Merged #{length(duplicates)} translations"))

      {:error, error} ->
        raise error
    end
  end

  defp merge_duplicate(
         {duplicate, _error_message, _line, _original_line},
         %Messages{messages: messages} = po
       ) do
    %Messages{
      po
      | messages:
          Enum.map(messages, fn message ->
            if Message.key(message) == Message.key(duplicate) do
              Message.merge(message, duplicate)
            else
              message
            end
          end)
    }
  end
end
