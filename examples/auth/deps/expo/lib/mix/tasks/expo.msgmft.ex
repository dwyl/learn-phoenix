defmodule Mix.Tasks.Expo.Msgfmt do
  @shortdoc "Generate binary message catalog from textual message description."

  @moduledoc """
  Generate binary message catalog from textual message description.

      mix expo.msgfmt [PO_FILE] [OPTIONS]

  ## Options

  * `--use-fuzzy` - use fuzzy entries in output
  * `--endianness=BYTEORDER` - write out 32-bit numbers in the given byte
    order (big or little, default depends on platform)
  * `--output-file=FILE` - write output to specified file
  * `--statistics` - print statistics about messages

  """

  use Mix.Task

  alias Expo.MO
  alias Expo.PO

  @switches [
    use_fuzzy: :boolean,
    endianness: :string,
    output_file: :string,
    statistics: :boolean
  ]
  @default_options [use_fuzzy: false, endianness: "little", statistics: false]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:expo)
    {opts, argv} = OptionParser.parse!(args, switches: @switches)

    opts = Keyword.merge(@default_options, opts)
    opts = Keyword.update!(opts, :endianness, &parse_endianness/1)
    {output_file, mo_compose_opts} = Keyword.pop(opts, :output_file)

    source_file =
      case argv do
        [] ->
          Mix.raise("""
          mix expo.msgfmt failed due to missing po file path argument
          """)

        [_file_one, _file_two | _other_files] ->
          Mix.raise("""
          mix expo.msgfmt failed due to multiple po file path arguments
          Only one is currently supported
          """)

        [file] ->
          file
      end

    messages = PO.parse_file!(source_file)

    output = MO.compose(messages, mo_compose_opts)

    case output_file do
      nil -> IO.binwrite(:standard_io, IO.iodata_to_binary(output))
      file -> File.write!(file, output)
    end

    if Keyword.fetch!(mo_compose_opts, :statistics) do
      receive do
        {MO, :message_count, count} ->
          # Not using Mix.shell().info/1 since that will print into stdout and not stderr
          IO.puts(:standard_error, "#{count} translated messages.")
      end
    end
  end

  defp parse_endianness(endianness)
  defp parse_endianness("little"), do: :little
  defp parse_endianness("big"), do: :big

  defp parse_endianness(other),
    do:
      Mix.raise("""
      mix expo.msgfmt failed due to invalid endianness option
      Expected: "little" or "big"
      Received: #{inspect(other)}
      """)
end
