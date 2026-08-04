defmodule Gettext.ExtractorAgent do
  @moduledoc false

  use Agent

  require Logger

  alias Expo.Message

  @name __MODULE__

  # :messages is a map where keys are Gettext backends and values
  # are maps. In these maps, keys are domains and values are maps of
  # message_id => message.
  # :backends is just a list of backends that call `use Gettext`.
  @initial_state %{
    messages: %{},
    backends: [],
    extracting?: false
  }

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link([] = _opts) do
    Agent.start_link(fn -> @initial_state end, name: @name)
  end

  @spec enable() :: :ok
  def enable() do
    Agent.update(@name, &put_in(&1.extracting?, true))
  end

  @spec disable() :: :ok
  def disable() do
    Agent.update(@name, &put_in(&1.extracting?, false))
  end

  @spec extracting?() :: boolean()
  def extracting?() do
    Agent.get(@name, & &1.extracting?)
  end

  @spec add_message(backend :: module(), domain :: String.t(), Message.t()) :: :ok
  def add_message(backend, domain, message) do
    key = Message.key(message)

    Agent.cast(@name, fn state ->
      # Initialize the given backend to an empty map if it wasn't there.
      state = update_in(state.messages, &Map.put_new(&1, backend, %{}))

      update_in(state.messages[backend][domain], fn messages ->
        Map.update(messages || %{}, key, message, &merge_messages(&1, message))
      end)
    end)
  end

  def add_backend(backend) do
    Agent.cast(@name, fn state ->
      update_in(state.backends, &[backend | &1])
    end)
  end

  def stop() do
    Agent.stop(@name)
  end

  def pop_message(backends) do
    Agent.get_and_update(@name, fn state ->
      get_and_update_in(state.messages, &Map.split(&1, backends))
    end)
  end

  def pop_backends(app) do
    Agent.get_and_update(@name, fn state ->
      get_and_update_in(state.backends, fn backends ->
        Enum.split_with(backends, &(&1.__gettext__(:otp_app) == app))
      end)
    end)
  end

  defp merge_messages(%Message.Singular{} = message_1, %Message.Plural{} = message_2) do
    # Flipping the arguments to make sure that the pluaral message (more information) is used as the base message
    merge_messages(message_2, message_1)
  end

  defp merge_messages(%Message.Plural{} = message_1, %Message.Plural{} = message_2) do
    # Make sure message choice is deterministic
    [message_1, message_2] =
      Enum.sort_by([message_1, message_2], &IO.iodata_to_binary(&1.msgid_plural))

    if IO.iodata_to_binary(message_1.msgid_plural) != IO.iodata_to_binary(message_2.msgid_plural) do
      Logger.warning("""
      Plural message for '#{IO.iodata_to_binary(message_1.msgid)}' is not matching:
      Using '#{IO.iodata_to_binary(message_2.msgid_plural)}' instead of '#{IO.iodata_to_binary(message_1.msgid_plural)}'.
      References: #{dump_references(message_1.references ++ message_2.references)}\
      """)
    end

    merge_messages_after_checks(message_1, message_2)
  end

  defp merge_messages(message_1, message_2), do: merge_messages_after_checks(message_1, message_2)

  defp merge_messages_after_checks(message_1, message_2) do
    message_1
    |> Map.put(:references, message_1.references ++ message_2.references)
    |> Map.put(
      :extracted_comments,
      Enum.uniq(message_1.extracted_comments ++ message_2.extracted_comments)
    )
  end

  defp dump_references(references) do
    references
    |> List.flatten()
    |> Enum.map(fn
      {file, line} -> [file, ":", Integer.to_string(line)]
      file -> file
    end)
    |> Enum.intersperse(", ")
  end
end
