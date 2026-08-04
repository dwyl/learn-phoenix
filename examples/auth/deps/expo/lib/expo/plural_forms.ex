defmodule Expo.PluralForms do
  @moduledoc """
  Functions to parse and evaluate plural forms as defined in the GNU Gettext documentation.

  The documentation is available at
  <https://www.gnu.org/software/gettext/manual/html_node/Plural-forms.html>.

  ## Usage

  Some functions in this module are considered "low level", and are meant to be
  used by other libraries. For example, `parse/1` returns an expression
  that is not really meant to be inspected, but rather used internally by this library.
  """

  alias Expo.PluralForms.SyntaxError
  alias Expo.PluralForms.Tokenizer

  defstruct [:nplurals, :plural]

  @typedoc """
  A struct representing a plural forms expression.
  """
  @type t() :: %__MODULE__{
          nplurals: pos_integer(),
          plural: plural_ast()
        }

  @typedoc """
  The AST of a plural forms expression.

  This is evaluated internally to determine the plural form for a given number
  using `index/2`, and is not meant to be inspected directly.
  """
  @opaque plural_ast() ::
            :n
            | integer()
            | {:!= | :> | :< | :== | :% | :<= | :>= | :&& | :||, plural_ast(), plural_ast()}
            | {:if, plural_ast(), plural_ast(), plural_ast()}
            | {:paren, plural_ast()}

  @doc """
  Parses a plural forms string into a `t:t/0` struct.

  Returns `{:ok, struct}` if the string is valid, or `{:error, error}`
  if it isn't.

  ### Examples

      iex> Expo.PluralForms.parse("nplurals=2; plural=n != 1;")
      {:ok, Expo.PluralForms.parse!("nplurals=2; plural=n != 1;")}

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, SyntaxError.t()}
  def parse(content) when is_binary(content) do
    with {:ok, tokens} <- Tokenizer.tokenize(content),
         {:ok, {nplurals, plural}} <- :expo_plural_forms_parser.parse(tokens) do
      {:ok, %__MODULE__{nplurals: nplurals, plural: plural}}
    else
      {:error, %SyntaxError{} = error} ->
        {:error, error}

      {:error, {position, :expo_plural_forms_parser, message}} ->
        message = IO.chardata_to_string(:expo_plural_forms_parser.format_error(message))
        {:error, %SyntaxError{reason: message, line: position, column: nil}}
    end
  end

  @doc """
  Parses a plural forms string into a `t:t/0` struct, raising if there are errors.

  Same as `parse/1`, but returns the plural forms struct directly if the
  parsing is successful, or raises an error otherwise.

  The `Inspect` implementation for the `Expo.PluralForms` struct uses this function
  to display the plural forms expression, which is why the example below might
  look a bit weird.

  ## Examples

      iex> Expo.PluralForms.parse!("nplurals=2; plural=n != 1;")
      Expo.PluralForms.parse!("nplurals=2; plural=n != 1;")

  """
  @spec parse!(String.t()) :: t()
  def parse!(content) do
    case parse(content) do
      {:ok, plural_forms} -> plural_forms
      {:error, error} -> raise error
    end
  end

  @doc """
  Converts a plural forms struct into its string representation.

  ## Examples

      iex> plural_forms = Expo.PluralForms.parse!("nplurals=2; plural=n != 1;")
      iex> Expo.PluralForms.to_string(plural_forms)
      "nplurals=2; plural=n != 1;"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{nplurals: nplurals, plural: plural_forms}) do
    IO.chardata_to_string([
      "nplurals=",
      Integer.to_string(nplurals),
      "; plural=",
      expr_to_string(plural_forms),
      ";"
    ])
  end

  defp expr_to_string(:n), do: "n"
  defp expr_to_string(number) when is_integer(number), do: Integer.to_string(number)

  defp expr_to_string({:if, condition, truthy, falsy}) do
    [expr_to_string(condition), " ? ", expr_to_string(truthy), " : ", expr_to_string(falsy)]
  end

  defp expr_to_string({:paren, content}) do
    ["(", expr_to_string(content), ")"]
  end

  defp expr_to_string({operator, left, right}) when operator in ~w(|| > < == % <= >=)a do
    [expr_to_string(left), Atom.to_string(operator), expr_to_string(right)]
  end

  defp expr_to_string({operator, left, right}) when operator in ~w(&& !=)a do
    [expr_to_string(left), " #{operator} ", expr_to_string(right)]
  end

  @doc """
  Gets the plural form for the given number based on the given `plural_forms` struct.

  ### Examples

      iex> {:ok, plural_form} = Expo.PluralForms.parse("nplurals=2; plural=n != 1;")
      iex> Expo.PluralForms.index(plural_form, 4)
      1
      iex> Expo.PluralForms.index(plural_form, 1)
      0

  """
  @spec index(t(), non_neg_integer()) :: non_neg_integer()
  def index(%__MODULE__{} = plural_form, n) do
    eval_ast(plural_form.plural, n)
  end

  defp eval_ast(:n, n) when is_integer(n), do: n
  defp eval_ast(number, _n) when is_integer(number), do: number

  defp eval_ast({:if, condition, truthy, falsy}, n) do
    ast = if eval_ast(condition, n) == 1, do: truthy, else: falsy
    eval_ast(ast, n)
  end

  defp eval_ast({:paren, content}, n), do: eval_ast(content, n)

  for op <- [:!=, :>, :<, :==, :>=, :<=] do
    defp eval_ast({unquote(op), left, right}, n) do
      bool_to_int(Kernel.unquote(op)(eval_ast(left, n), eval_ast(right, n)))
    end
  end

  for op <- [:&&, :||] do
    defp eval_ast({unquote(op), left, right}, n) do
      bool_to_int(Kernel.unquote(op)(eval_ast(left, n) == 1, eval_ast(right, n) == 1))
    end
  end

  defp eval_ast({:%, left, right}, n), do: rem(eval_ast(left, n), eval_ast(right, n))

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  @doc """
  Gets the plural form for the given language based on built-in information.

  ### Examples

      iex> Expo.PluralForms.plural_form("de")
      {:ok, Expo.PluralForms.parse!("nplurals=2; plural=(n != 1);")}

      iex> Expo.PluralForms.plural_form("invalid")
      :error

  """
  @spec plural_form(String.t()) :: {:ok, t()} | :error
  defdelegate plural_form(iso_language_tag), to: Expo.PluralForms.Known

  @doc """
  Get known locales where plural form information is available.

  ### Examples

      iex> "de" in Expo.PluralForms.known_locales()
      true

      iex> "invalid" in Expo.PluralForms.known_locales()
      false

  """
  @spec known_locales() :: [String.t(), ...]
  defdelegate known_locales(), to: Expo.PluralForms.Known

  # Inspect protocol for the struct, so that we don't print its internals (and we are free to
  # change them later on).
  defimpl Inspect do
    import Inspect.Algebra

    @spec inspect(@for.t(), Inspect.Opts.t()) :: Inspect.Algebra.t()
    def inspect(%@for{} = struct, opts) do
      concat(["Expo.PluralForms.parse!(", @protocol.inspect(@for.to_string(struct), opts), ")"])
    end
  end
end
