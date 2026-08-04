defmodule DBConnection.Backoff do
  # This module provides a functional abstraction over backoffs with different types. It exposes
  # a struct and a couple of functions to work with it.
  @moduledoc false
  @compile :nowarn_deprecated_function

  alias DBConnection.Backoff

  @default_type :rand_exp
  @min 1_000
  @max 30_000

  @type t :: %__MODULE__{
          type: :stop | :rand | :exp | :rand_exp,
          min: non_neg_integer(),
          max: non_neg_integer(),
          state: term()
        }

  defstruct [:type, :min, :max, :state]

  @spec new(keyword) :: t | nil
  def new(opts) when is_list(opts) do
    case Keyword.get(opts, :backoff_type, @default_type) do
      :stop ->
        nil

      type ->
        {min, max} = min_max(opts)
        new(type, min, max)
    end
  end

  @spec backoff(t) :: {non_neg_integer, t}
  def backoff(backoff)

  def backoff(%Backoff{type: :rand, min: min, max: max} = s) do
    {rand(min, max), s}
  end

  def backoff(%Backoff{type: :exp, min: min, state: nil} = s) do
    {min, %{s | state: min}}
  end

  def backoff(%Backoff{type: :exp, max: max, state: prev} = s) do
    require Bitwise
    next = min(Bitwise.<<<(prev, 1), max)
    {next, %{s | state: next}}
  end

  def backoff(%Backoff{type: :rand_exp, max: max, state: state} = s) do
    {prev, lower} = state
    next_min = min(prev, lower)
    next_max = min(prev * 3, max)
    next = rand(next_min, next_max)
    {next, %{s | state: {next, lower}}}
  end

  @spec reset(t) :: t
  def reset(backoff)

  def reset(%Backoff{type: :rand} = s), do: s
  def reset(%Backoff{type: :exp} = s), do: %{s | state: nil}

  def reset(%Backoff{type: :rand_exp, min: min, state: {_, lower}} = s) do
    %{s | state: {min, lower}}
  end

  ## Internal

  defp min_max(opts) do
    case {opts[:backoff_min], opts[:backoff_max]} do
      {nil, nil} -> {@min, @max}
      {nil, max} -> {min(@min, max), max}
      {min, nil} -> {min, max(min, @max)}
      {min, max} -> {min, max}
    end
  end

  defp new(_, min, _) when not (is_integer(min) and min >= 0) do
    raise ArgumentError, "minimum #{inspect(min)} not 0 or a positive integer"
  end

  defp new(_, _, max) when not (is_integer(max) and max >= 0) do
    raise ArgumentError, "maximum #{inspect(max)} not 0 or a positive integer"
  end

  defp new(_, min, max) when min > max do
    raise ArgumentError, "minimum #{min} is greater than maximum #{max}"
  end

  defp new(:rand, min, max) do
    %Backoff{type: :rand, min: min, max: max, state: nil}
  end

  defp new(:exp, min, max) do
    %Backoff{type: :exp, min: min, max: max, state: nil}
  end

  defp new(:rand_exp, min, max) do
    lower = max(min, div(max, 3))
    %Backoff{type: :rand_exp, min: min, max: max, state: {min, lower}}
  end

  defp new(type, _, _) do
    raise ArgumentError, "unknown type #{inspect(type)}"
  end

  defp rand(min, max) do
    :rand.uniform(max - min + 1) + min - 1
  end
end
