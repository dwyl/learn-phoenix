defmodule Gettext.Interpolation.Default do
  @moduledoc """
  Default implementation for the `Gettext.Interpolation` behaviour.

  Replaces `%{binding_name}` with the string value of the `binding_name` binding.
  """

  @behaviour Gettext.Interpolation

  @typedoc """
  Something that can be interpolated.

  It's either a string (a literal) or an atom (representing a binding name).
  """
  @type interpolatable() :: [String.t() | atom()]

  # Extracts interpolations from a given string.

  # This function extracts all interpolations in the form `%{interpolation}`
  # contained inside `str`, converts them to atoms and then returns a list of
  # string and interpolation keys.
  @doc false
  @spec to_interpolatable(String.t()) :: interpolatable()
  def to_interpolatable(string) when is_binary(string) do
    start_pattern = :binary.compile_pattern("%{")
    end_pattern = :binary.compile_pattern("}")

    string
    |> to_interpolatable(_current = "", _acc = [], start_pattern, end_pattern)
    |> Enum.reverse()
  end

  defp to_interpolatable(string, current, acc, start_pattern, end_pattern) do
    case :binary.split(string, start_pattern) do
      # If we have one element, no %{ was found so this is the final part of the
      # string.
      [rest] ->
        prepend_if_not_empty(current <> rest, acc)

      # If we found a %{ but it's followed by an immediate }, then we just
      # append %{} to the current string and keep going.
      [before, "}" <> rest] ->
        new_current = current <> before <> "%{}"
        to_interpolatable(rest, new_current, acc, start_pattern, end_pattern)

      # Otherwise, we found the start of a binding.
      [before, binding_and_rest] ->
        case :binary.split(binding_and_rest, end_pattern) do
          # If we don't find the end of this binding, it means we're at a string
          # like "foo %{ no end". In this case we consider no bindings to be
          # there.
          [_] ->
            [current <> string | acc]

          # This is the case where we found a binding, so we put it in the acc
          # and keep going.
          [binding, rest] ->
            new_acc = [String.to_atom(binding) | prepend_if_not_empty(before, acc)]
            to_interpolatable(rest, "", new_acc, start_pattern, end_pattern)
        end
    end
  end

  defp prepend_if_not_empty("", list), do: list
  defp prepend_if_not_empty(string, list), do: [string | list]

  @doc """
  Interpolate a message or interpolatable with the given bindings.

  Implementation of the `c:Gettext.Interpolation.runtime_interpolate/2` callback.

  This function takes a message and some bindings and returns an `{:ok,
  interpolated_string}` tuple if interpolation is successful. If it encounters
  a binding in the message that is missing from `bindings`, it returns
  `{:missing_bindings, incomplete_string, missing_bindings}` where
  `incomplete_string` is the string with only the present bindings interpolated
  and `missing_bindings` is a list of atoms representing bindings that are in
  `interpolatable` but not in `bindings`.

  ## Examples

      iex> msgid = "Hello %{name}, you have %{count} unread messages"
      iex> good_bindings = %{name: "José", count: 3}
      iex> Gettext.Interpolation.Default.runtime_interpolate(msgid, good_bindings)
      {:ok, "Hello José, you have 3 unread messages"}
      iex> Gettext.Interpolation.Default.runtime_interpolate(msgid, %{name: "José"})
      {:missing_bindings, "Hello José, you have %{count} unread messages", [:count]}

      iex> msgid = "Hello %{name}, you have %{count} unread messages"
      iex> interpolatable = Gettext.Interpolation.Default.to_interpolatable(msgid)
      iex> good_bindings = %{name: "José", count: 3}
      iex> Gettext.Interpolation.Default.runtime_interpolate(interpolatable, good_bindings)
      {:ok, "Hello José, you have 3 unread messages"}
      iex> Gettext.Interpolation.Default.runtime_interpolate(interpolatable, %{name: "José"})
      {:missing_bindings, "Hello José, you have %{count} unread messages", [:count]}

  """
  @impl true
  def runtime_interpolate(message, bindings)

  def runtime_interpolate(message, %{} = bindings) when is_binary(message) do
    message |> to_interpolatable() |> runtime_interpolate(bindings)
  end

  def runtime_interpolate(interpolatable, %{} = bindings) when is_list(interpolatable) do
    interpolate(interpolatable, bindings, [], [])
  end

  defp interpolate([string | segments], bindings, strings, missing) when is_binary(string) do
    interpolate(segments, bindings, [string | strings], missing)
  end

  defp interpolate([atom | segments], bindings, strings, missing) when is_atom(atom) do
    case bindings do
      %{^atom => value} ->
        interpolate(segments, bindings, [to_string(value) | strings], missing)

      %{} ->
        strings = ["%{" <> Atom.to_string(atom) <> "}" | strings]
        interpolate(segments, bindings, strings, [atom | missing])
    end
  end

  defp interpolate([], _bindings, strings, []) do
    {:ok, IO.iodata_to_binary(Enum.reverse(strings))}
  end

  defp interpolate([], _bindings, strings, missing) do
    missing = missing |> Enum.reverse() |> Enum.uniq()
    {:missing_bindings, IO.iodata_to_binary(Enum.reverse(strings)), missing}
  end

  # Returns all the interpolation keys contained in the given string or list of
  # segments.

  # This function returns a list of all the interpolation keys (patterns in the
  # form `%{interpolation}`) contained in its argument.

  # If the argument is a segment list, that is, a list of strings and atoms where
  # atoms represent interpolation keys, then only the atoms in the list are
  # returned.
  @doc false
  @spec keys(String.t() | interpolatable()) :: [atom()]
  def keys(string_or_interpolatable)

  def keys(string) when is_binary(string), do: string |> to_interpolatable() |> keys()

  def keys(interpolatable) when is_list(interpolatable),
    do: interpolatable |> Enum.filter(&is_atom/1) |> Enum.uniq()

  @doc """
  Compiles a static message to interpolate with dynamic bindings.

  Implementation of the `c:Gettext.Interpolation.compile_interpolate/3` macro callback.

  Takes a static message and some dynamic bindings. The generated
  code will return an `{:ok, interpolated_string}` tuple if the interpolation
  is successful. If it encounters a binding in the message that is missing from
  `bindings`, it returns `{:missing_bindings, incomplete_string, missing_bindings}`,
  where `incomplete_string` is the string with only the present bindings interpolated
  and `missing_bindings` is a list of atoms representing bindings that are in
  `interpolatable` but not in `bindings`.
  """
  @impl true
  defmacro compile_interpolate(message_type, message, bindings) do
    unless is_binary(message) do
      raise """
      #{inspect(__MODULE__)}.compile_interpolate/2 can only be used at compile time with \
      static messages. Alternatively, use #{inspect(__MODULE__)}.runtime_interpolate/2.
      """
    end

    interpolatable = to_interpolatable(message)
    keys = keys(interpolatable)
    match_clause = match_clause(keys)
    compile_string = compile_string(interpolatable)

    case {keys, message_type} do
      # If no keys are in the message, the message can be returned without interpolation
      {[], _message_type} ->
        quote do: {:ok, unquote(message)}

      # If the message only contains the key `count` and it is a plural message,
      # gettext ensures that `count` is always set. Therefore the dynamic interpolation
      # will never be needed.
      {[:count], :plural_translation} ->
        quote do
          unquote(match_clause) = unquote(bindings)
          {:ok, unquote(compile_string)}
        end

      {_keys, _message_type} ->
        quote do
          case unquote(bindings) do
            unquote(match_clause) ->
              {:ok, unquote(compile_string)}

            %{} = other_bindings ->
              unquote(__MODULE__).runtime_interpolate(unquote(interpolatable), other_bindings)
          end
        end
    end
  end

  # Compiles a list of atoms into a "match" map. For example `[:foo, :bar]` gets
  # compiled to `%{foo: foo, bar: bar}`. All generated variables are under the
  # current `__MODULE__`.
  defp match_clause(keys) do
    {:%{}, [], Enum.map(keys, &{&1, Macro.var(&1, __MODULE__)})}
  end

  # Compiles a string into a binary with `%{var}` patterns turned into `var`
  # variables, namespaced inside the current `__MODULE__`.
  defp compile_string(interpolatable) do
    parts =
      Enum.map(interpolatable, fn
        key when is_atom(key) ->
          quote do: to_string(unquote(Macro.var(key, __MODULE__))) :: binary

        str ->
          str
      end)

    {:<<>>, [], parts}
  end

  @doc """
  Implementation of `c:Gettext.Interpolation.message_format/0`.

  ## Examples

      iex> Gettext.Interpolation.Default.message_format()
      "elixir-format"

  """
  @impl true
  def message_format, do: "elixir-format"
end
