defmodule Expo.PluralForms.Tokenizer do
  @moduledoc false

  alias Expo.PluralForms.SyntaxError

  @type token() :: {atom(), pos_integer()} | {:int, pos_integer(), non_neg_integer()}

  @operators [:==, :!=, :>=, :<=, :>, :<, :=, :"?", :":", :%, :||, :&&, :";", :")", :"("]
  @keywords [:nplurals, :plural, :n]

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, SyntaxError.t()}
  def tokenize(string) when is_binary(string) do
    tokenize(string, _acc = [], _line = 1, _col = 1)
  end

  defp tokenize(<<>>, acc, line, _col) do
    {:ok, Enum.reverse([{:"$end", line} | acc])}
  end

  defp tokenize(<<?\n, rest::binary>>, acc, line, _col), do: tokenize(rest, acc, line + 1, 1)
  defp tokenize(<<?\s, rest::binary>>, acc, line, col), do: tokenize(rest, acc, line, col + 1)

  for keyword_or_operator <- @keywords ++ @operators do
    str = Atom.to_string(keyword_or_operator)
    len = byte_size(str)

    defp tokenize(<<unquote(str), rest::binary>>, acc, line, col) do
      tokenize(rest, [{unquote(keyword_or_operator), line} | acc], line, col + unquote(len))
    end
  end

  defp tokenize(<<digit, _rest::binary>> = str, acc, line, col) when digit in ?0..?9 do
    {int, rest} = Integer.parse(str)
    len = byte_size(str) - byte_size(rest)
    tokenize(rest, [{:int, line, int} | acc], line, col + len)
  end

  defp tokenize(<<char::binary-size(1), _rest::binary>>, _acc, line, col) do
    reason = "unexpected token: #{inspect(char)}"
    {:error, %SyntaxError{reason: reason, line: line, column: col}}
  end
end
