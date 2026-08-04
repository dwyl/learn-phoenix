defmodule NimbleOptions do
  @options_schema [
    *: [
      type: :keyword_list,
      keys: [
        type: [
          type: {:custom, __MODULE__, :validate_type, []},
          default: :any,
          doc: "The type of the option item."
        ],
        required: [
          type: :boolean,
          default: false,
          doc: "Defines if the option item is required."
        ],
        default: [
          type: :any,
          doc: """
          The default value for the option item if that option is not specified. This value
          is *validated* according to the given `:type`. This means that you cannot
          have, for example, `type: :integer` and use `default: "a string"`.
          """
        ],
        keys: [
          type: :keyword_list,
          doc: """
          Available for types `:keyword_list`, `:non_empty_keyword_list`, and `:map`,
          it defines which set of keys are accepted for the option item. The value of the
          `:keys` option is a schema itself. For example: `keys: [foo: [type: :atom]]`.
          Use `:*` as the key to allow multiple arbitrary keys and specify their schema:
          `keys: [*: [type: :integer]]`.
          """,
          keys: &__MODULE__.options_schema/0
        ],
        deprecated: [
          type: :string,
          doc: """
          Defines a message to indicate that the option item is deprecated. \
          The message will be displayed as a warning when passing the item.
          """
        ],
        doc: [
          type: {:or, [:string, {:in, [false]}]},
          type_doc: "`t:String.t/0` or `false`",
          doc: "The documentation for the option item."
        ],
        subsection: [
          type: :string,
          doc: "The title of separate subsection of the options' documentation"
        ],
        type_doc: [
          type: {:or, [:string, {:in, [false]}]},
          type_doc: "`t:String.t/0` or `false`",
          doc: """
          The type doc to use *in the documentation* for the option item. If `false`,
          no type documentation is added to the item. If it's a string, it can be
          anything. For example, you can use `"a list of PIDs"`, or you can use
          a typespec reference that ExDoc can link to the type definition, such as
          `` "`t:binary/0`" ``. You can use Markdown in this documentation. If the
          `:type_doc` option is not present, NimbleOptions tries to produce a type
          documentation automatically if it can do it unambiguously. For example,
          if `type: :integer`, NimbleOptions will use `t:integer/0` as the
          auto-generated type doc.
          """
        ],
        type_spec: [
          type: :any,
          type_doc: "`t:Macro.t/0`",
          doc: """
          The quoted spec to use *in the typespec* for the option item. You should use this
          when the auto-generated spec is not specific enough. For example, if you are performing
          custom validation on an option (with the `{:custom, ...}` type), then the
          generated type spec for that option will always be `t:term/0`, but you can use
          this option to customize that. The value for this option **must** be a quoted Elixir
          term. For example, if you have an `:exception` option that is validated with a
          `{:custom, ...}` type (based on `is_exception/1`), you can override the type
          spec for that option to be `quote(do: Exception.t())`. *Available since v1.1.0*.
          """
        ]
      ]
    ]
  ]

  @moduledoc """
  Provides a standard API to handle keyword-list-based options.

  `NimbleOptions` allows developers to create schemas using a
  pre-defined set of options and types. The main benefits are:

    * A single unified way to define simple static options
    * Config validation against schemas
    * Automatic doc generation

  ## Schema Options

  These are the options supported in a *schema*. They are what
  defines the validation for the items in the given schema.

  #{NimbleOptions.Docs.generate(@options_schema, nest_level: 0)}

  ## Types

    * `:any` - Any type.

    * `:keyword_list` - A keyword list.

    * `:non_empty_keyword_list` - A non-empty keyword list.

    * `:map` - A map consisting of `:atom` keys. Shorthand for `{:map, :atom, :any}`.
      Keys can be specified using the `keys` option.

    * `{:map, key_type, value_type}` - A map consisting of `key_type` keys and
      `value_type` values.

    * `:atom` - An atom.

    * `:string` - A string.

    * `:boolean` - A boolean.

    * `:integer` - An integer.

    * `:non_neg_integer` - A non-negative integer.

    * `:pos_integer` - A positive integer.

    * `:float` - A float.

    * `:timeout` - A non-negative integer or the atom `:infinity`.

    * `:pid` - A PID (process identifier).

    * `:reference` - A reference (see `t:reference/0`).

    * `nil` - The value `nil` itself. Available since v1.0.0.

    * `:mfa` - A named function in the format `{module, function, arity}` where
      `arity` is a list of arguments. For example, `{MyModule, :my_fun, [arg1, arg2]}`.

    * `:mod_arg` - A module along with arguments, such as `{MyModule, arguments}`.
      Usually used for process initialization using `start_link` and similar. The
      second element of the tuple can be any term.

    * `{:fun, arity}` - Any function with the specified arity.

    * `{:in, choices}` - A value that is a member of one of the `choices`. `choices`
      should be a list of terms or a `Range`. The value is an element in said
      list of terms, that is, `value in choices` is `true`. This was previously
      called `:one_of` and the `:in` name is available since version 0.3.3 (`:one_of`
      has been removed in v0.4.0).

    * `{:custom, mod, fun, args}` - A custom type. The related value must be validated
      by `mod.fun(values, ...args)`. The function should return `{:ok, value}` or
      `{:error, message}`.

    * `{:or, subtypes}` - A value that matches one of the given `subtypes`. The value is
      matched against the subtypes in the order specified in the list of `subtypes`. If
      one of the subtypes matches and **updates** (casts) the given value, the updated
      value is used. For example: `{:or, [:string, :boolean, {:fun, 2}]}`. If one of the
      subtypes is a keyword list or map, you won't be able to pass `:keys` directly. For this reason,
      `:keyword_list`, `:non_empty_keyword_list`, and `:map` are special cased and can
      be used as subtypes with `{:keyword_list, keys}`, `{:non_empty_keyword_list, keys}` or `{:map, keys}`.
      For example, a type such as `{:or, [:boolean, keyword_list: [enabled: [type: :boolean]]]}`
      would match either a boolean or a keyword list with the `:enabled` boolean option in it.

    * `{:list, subtype}` - A list where all elements match `subtype`. `subtype` can be any
      of the accepted types listed here. Empty lists are allowed. The resulting validated list
      contains the validated (and possibly updated) elements, each as returned after validation
      through `subtype`. For example, if `subtype` is a custom validator function that returns
      an updated value, then that updated value is used in the resulting list. Validation
      fails at the *first* element that is invalid according to `subtype`. If `subtype` is
      a keyword list or map, you won't be able to pass `:keys` directly. For this reason,
      `:keyword_list`, `:non_empty_keyword_list`, and `:map` are special cased and can
      be used as the subtype by using `{:keyword_list, keys}`, `{:non_empty_keyword_list, keys}`
      or `{:keyword_list, keys}`. For example, a type such as
      `{:list, {:keyword_list, enabled: [type: :boolean]}}` would a *list of keyword lists*,
      where each keyword list in the list could have the `:enabled` boolean option in it.

    * `{:tuple, list_of_subtypes}` - A tuple as described by `tuple_of_subtypes`.
      `list_of_subtypes` must be a list with the same length as the expected tuple.
      Each of the list's elements must be a subtype that should match the given element in that
      same position. For example, to describe 3-element tuples with an atom, a string, and
      a list of integers you would use the type `{:tuple, [:atom, :string, {:list, :integer}]}`.
      *Available since v0.4.1*.

    * `{:struct, struct_name}` - An instance of the struct type given.

  ## Example

      iex> schema = [
      ...>   producer: [
      ...>     type: :non_empty_keyword_list,
      ...>     required: true,
      ...>     keys: [
      ...>       module: [required: true, type: :mod_arg],
      ...>       concurrency: [
      ...>         type: :pos_integer,
      ...>       ]
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> config = [
      ...>   producer: [
      ...>     concurrency: 1,
      ...>   ]
      ...> ]
      ...>
      ...> {:error, %NimbleOptions.ValidationError{} = error} = NimbleOptions.validate(config, schema)
      ...> Exception.message(error)
      "required :module option not found, received options: [:concurrency] (in options [:producer])"

  ## Nested Option Items

  `NimbleOptions` allows option items to be nested so you can recursively validate
  any item down the options tree.

  ### Example

      iex> schema = [
      ...>   producer: [
      ...>     required: true,
      ...>     type: :non_empty_keyword_list,
      ...>     keys: [
      ...>       rate_limiting: [
      ...>         type: :non_empty_keyword_list,
      ...>         keys: [
      ...>           interval: [required: true, type: :pos_integer]
      ...>         ]
      ...>       ]
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> config = [
      ...>   producer: [
      ...>     rate_limiting: [
      ...>       interval: :oops!
      ...>     ]
      ...>   ]
      ...> ]
      ...>
      ...> {:error, %NimbleOptions.ValidationError{} = error} = NimbleOptions.validate(config, schema)
      ...> Exception.message(error)
      "invalid value for :interval option: expected positive integer, got: :oops! (in options [:producer, :rate_limiting])"

  ## Validating Schemas

  Each time `validate/2` is called, the given schema itself will be validated before validating
  the options.

  In most applications the schema will never change but validating options will be done
  repeatedly.

  To avoid the extra cost of validating the schema, it is possible to validate the schema once,
  and then use that valid schema directly. This is done by using the `new!/1` function first, and
  then passing the returned schema to `validate/2`.

  > #### Create the Schema at Compile Time {: .tip}
  >
  > If your option schema doesn't include any runtime-only terms in it (such as anonymous
  > functions), you can call `new!/1` to validate the schema and returned a *compiled* schema
  > **at compile time**. This is an efficient way to avoid doing any unnecessary work at
  > runtime. See the example below for more information.

  ### Example

      iex> raw_schema = [
      ...>   hostname: [
      ...>     required: true,
      ...>     type: :string
      ...>   ]
      ...> ]
      ...>
      ...> schema = NimbleOptions.new!(raw_schema)
      ...> NimbleOptions.validate([hostname: "elixir-lang.org"], schema)
      {:ok, hostname: "elixir-lang.org"}

  Calling `new!/1` from a function that receives options will still validate the schema each time
  that function is called. Declaring the schema as a module attribute is supported:

      @options_schema NimbleOptions.new!([...])

  This schema will be validated at compile time. Calling `docs/1` on that schema is also
  supported.
  """

  alias NimbleOptions.ValidationError

  defstruct schema: []

  @basic_types [
    :any,
    :keyword_list,
    :non_empty_keyword_list,
    :map,
    :atom,
    :integer,
    :non_neg_integer,
    :pos_integer,
    :float,
    :mfa,
    :mod_arg,
    :string,
    :boolean,
    :timeout,
    :pid,
    :reference,
    nil
  ]

  @typedoc """
  A schema.

  See the module documentation for more information.
  """
  @type schema() :: keyword()

  @typedoc """
  The `NimbleOptions` struct embedding a validated schema.

  See the [*Validating Schemas* section](#module-validating-schemas) in
  the module documentation.
  """
  @type t() :: %__MODULE__{schema: schema()}

  @doc """
  Validates the given `options` with the given `schema`.

  See the module documentation for what a `schema` is.

  If the validation is successful, this function returns `{:ok, validated_options}`
  where `validated_options` is a keyword list. If the validation fails, this
  function returns `{:error, validation_error}` where `validation_error` is a
  `NimbleOptions.ValidationError` struct explaining what's wrong with the options.
  You can use `raise/1` with that struct or `Exception.message/1` to turn it into a string.
  """
  @spec validate(keyword() | map(), schema() | t()) ::
          {:ok, validated_options :: keyword() | map()} | {:error, ValidationError.t()}

  def validate(options, %NimbleOptions{schema: schema}) do
    validate_options_with_schema(options, schema)
  end

  def validate(options, schema) when is_list(options) and is_list(schema) do
    validate(options, new!(schema))
  end

  @doc """
  Validates the given `options` with the given `schema` and raises if they're not valid.

  This function behaves exactly like `validate/2`, but returns the options directly
  if they're valid or raises a `NimbleOptions.ValidationError` exception otherwise.
  """
  @spec validate!(keyword() | map(), schema() | t()) :: validated_options :: keyword() | map()
  def validate!(options, schema) do
    case validate(options, schema) do
      {:ok, options} -> options
      {:error, %ValidationError{} = error} -> raise error
    end
  end

  @doc """
  Validates the given `schema` and returns a wrapped schema to be used with `validate/2`.

  If the given schema is not valid, raises a `NimbleOptions.ValidationError`.
  """
  @spec new!(schema()) :: t()
  def new!(schema) when is_list(schema) do
    case validate_options_with_schema(schema, options_schema()) do
      {:ok, validated_schema} ->
        %NimbleOptions{schema: validated_schema}

      {:error, %ValidationError{} = error} ->
        raise ArgumentError,
              "invalid NimbleOptions schema. Reason: #{Exception.message(error)}"
    end
  end

  @doc ~S"""
  Returns documentation for the given schema.

  You can use this to inject documentation in your docstrings. For example,
  say you have your schema in a module attribute:

      @options_schema [...]

  With this, you can use `docs/1` to inject documentation:

      @doc "Supported options:\n#{NimbleOptions.docs(@options_schema)}"

  ## Options

    * `:nest_level` - an integer deciding the "nest level" of the generated
      docs. This is useful when, for example, you use `docs/2` inside the `:doc`
      option of another schema. For example, if you have the following nested schema:

          nested_schema = [
            allowed_messages: [type: :pos_integer, doc: "Allowed messages."],
            interval: [type: :pos_integer, doc: "Interval."]
          ]

      then you can document it inside another schema with its nesting level increased:

          schema = [
            producer: [
              type: {:or, [:string, keyword_list: nested_schema]},
              doc:
                "Either a string or a keyword list with the following keys:\n\n" <>
                  NimbleOptions.docs(nested_schema, nest_level: 1)
            ],
            other_key: [type: :string]
          ]

  """
  @spec docs(schema() | t(), keyword()) :: String.t()
  def docs(schema, options \\ [])

  def docs(schema, options) when is_list(schema) and is_list(options) do
    NimbleOptions.Docs.generate(schema, options)
  end

  def docs(%NimbleOptions{schema: schema}, options) when is_list(options) do
    NimbleOptions.Docs.generate(schema, options)
  end

  @doc """
  Returns the quoted typespec for any option described by the given schema.

  The returned quoted code represents the **type union** for all possible
  keys in the schema, alongside their type. Nested keyword lists are
  spec'ed as `t:keyword/0`.

  ## Usage

  Because of how typespecs are treated by the Elixir compiler, you have
  to use `unquote/1` on the return value of this function to use it
  in a typespec:

      @type option() :: unquote(NimbleOptions.option_typespec(my_schema))

  This function returns the type union for a single option: to give you
  flexibility to combine it and use it in your own typespecs. For example,
  if you only validate part of the options through NimbleOptions, you could
  write a spec like this:

      @type my_option() ::
              {:my_opt1, integer()}
              | {:my_opt2, boolean()}
              | unquote(NimbleOptions.option_typespec(my_schema))

  If you want to spec a whole schema, you could write something like this:

      @type options() :: [unquote(NimbleOptions.option_typespec(my_schema))]

  ## Example

      schema = [
        int: [type: :integer],
        number: [type: {:or, [:integer, :float]}]
      ]

      @type option() :: unquote(NimbleOptions.option_typespec(schema))

  The code above would essentially compile to:

      @type option() :: {:int, integer()} | {:number, integer() | float()}

  """
  @doc since: "0.5.0"
  @spec option_typespec(schema() | t()) :: Macro.t()
  def option_typespec(schema)

  def option_typespec(schema) when is_list(schema) do
    NimbleOptions.Docs.schema_to_spec(schema)
  end

  def option_typespec(%NimbleOptions{schema: schema}) do
    NimbleOptions.Docs.schema_to_spec(schema)
  end

  @doc false
  def options_schema() do
    @options_schema
  end

  defp validate_options_with_schema(opts, schema) do
    validate_options_with_schema_and_path(opts, schema, _path = [])
  end

  defp validate_options_with_schema_and_path(opts, fun, path) when is_function(fun) do
    validate_options_with_schema_and_path(opts, fun.(), path)
  end

  defp validate_options_with_schema_and_path(opts, schema, path) when is_map(opts) do
    list_opts = Map.to_list(opts)

    case validate_options_with_schema_and_path(list_opts, schema, path) do
      {:ok, validated_list_opts} -> {:ok, Map.new(validated_list_opts)}
      error -> error
    end
  end

  defp validate_options_with_schema_and_path(opts, schema, path) when is_list(opts) do
    schema = expand_star_to_option_keys(schema, opts)

    with :ok <- validate_unknown_options(opts, schema),
         {:ok, options} <- validate_options(opts, schema) do
      {:ok, options}
    else
      {:error, %ValidationError{} = error} ->
        {:error, %ValidationError{error | keys_path: path ++ error.keys_path}}
    end
  end

  defp validate_unknown_options(opts, schema) do
    valid_opts = Keyword.keys(schema)

    case Keyword.keys(opts) -- valid_opts do
      [] ->
        :ok

      keys ->
        error_tuple(
          keys,
          nil,
          "unknown options #{inspect(keys)}, valid options are: #{inspect(valid_opts)}"
        )
    end
  end

  defp validate_options(opts, schema) do
    orig_opts = opts

    case Enum.reduce_while(schema, {opts, orig_opts}, &reduce_options/2) do
      {:error, %ValidationError{}} = result -> result
      {opts, _orig_opts} -> {:ok, opts}
    end
  end

  defp reduce_options({key, schema_opts}, {opts, orig_opts}) do
    case validate_option({opts, orig_opts}, key, schema_opts) do
      {:error, %ValidationError{}} = result ->
        {:halt, result}

      {:ok, value} ->
        opts = Keyword.update(opts, key, value, fn _ -> value end)
        {:cont, {opts, orig_opts}}

      :no_value ->
        if Keyword.has_key?(schema_opts, :default) do
          opts_with_default = Keyword.put(opts, key, schema_opts[:default])
          reduce_options({key, schema_opts}, {opts_with_default, orig_opts})
        else
          {:cont, {opts, orig_opts}}
        end
    end
  end

  defp validate_option({opts, orig_opts}, key, schema) do
    with {:ok, value} <- validate_value({opts, orig_opts}, key, schema),
         {:ok, value} <- validate_type(schema[:type], key, value) do
      if nested_schema = schema[:keys] do
        validate_options_with_schema_and_path(value, nested_schema, _path = [key])
      else
        {:ok, value}
      end
    end
  end

  defp validate_value({opts, orig_opts}, key, schema) do
    cond do
      Keyword.has_key?(opts, key) ->
        if message = Keyword.get(schema, :deprecated) do
          IO.warn("#{render_key(key)} is deprecated. " <> message)
        end

        {:ok, opts[key]}

      Keyword.get(schema, :required, false) ->
        error_tuple(
          key,
          nil,
          "required #{render_key(key)} not found, received options: " <>
            inspect(Keyword.keys(orig_opts))
        )

      true ->
        :no_value
    end
  end

  defp validate_type(:integer, key, value) when not is_integer(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected integer, got: #{inspect(value)}"
    )
  end

  defp validate_type(:non_neg_integer, key, value) when not is_integer(value) or value < 0 do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected non negative integer, got: #{inspect(value)}"
    )
  end

  defp validate_type(:pos_integer, key, value) when not is_integer(value) or value < 1 do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected positive integer, got: #{inspect(value)}"
    )
  end

  defp validate_type(:float, key, value) when not is_float(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected float, got: #{inspect(value)}"
    )
  end

  defp validate_type(:atom, key, value) when not is_atom(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected atom, got: #{inspect(value)}"
    )
  end

  defp validate_type(:timeout, key, value)
       when not (value == :infinity or (is_integer(value) and value >= 0)) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected non-negative integer or :infinity, got: #{inspect(value)}"
    )
  end

  defp validate_type(:string, key, value) when not is_binary(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected string, got: #{inspect(value)}"
    )
  end

  defp validate_type(:boolean, key, value) when not is_boolean(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected boolean, got: #{inspect(value)}"
    )
  end

  defp validate_type(:keyword_list, key, value) do
    if keyword_list?(value) do
      {:ok, value}
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected keyword list, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(:non_empty_keyword_list, key, value) do
    if keyword_list?(value) and value != [] do
      {:ok, value}
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected non-empty keyword list, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(:map, key, value) do
    validate_type({:map, :atom, :any}, key, value)
  end

  defp validate_type({:map, key_type, value_type}, key, map) when is_map(map) do
    map
    |> Enum.reduce_while([], fn {key, value}, acc ->
      with {:ok, updated_key} <- validate_type(key_type, {__MODULE__, :key}, key),
           {:ok, updated_value} <- validate_type(value_type, {__MODULE__, :value, key}, value) do
        {:cont, [{updated_key, updated_value} | acc]}
      else
        {:error, %ValidationError{} = error} -> {:halt, error}
      end
    end)
    |> case do
      pairs when is_list(pairs) ->
        {:ok, Map.new(pairs)}

      %ValidationError{} = error ->
        error_tuple(key, map, "invalid map in #{render_key(key)}: #{error.message}")
    end
  end

  defp validate_type({:map, _, _}, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected map, got: #{inspect(value)}"
    )
  end

  defp validate_type(:pid, _key, value) when is_pid(value) do
    {:ok, value}
  end

  defp validate_type(:pid, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected pid, got: #{inspect(value)}"
    )
  end

  defp validate_type(:reference, _key, value) when is_reference(value) do
    {:ok, value}
  end

  defp validate_type(:reference, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected reference, got: #{inspect(value)}"
    )
  end

  defp validate_type(:mfa, _key, {mod, fun, args} = value)
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    {:ok, value}
  end

  defp validate_type(:mfa, key, value) when not is_nil(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected tuple {mod, fun, args}, got: #{inspect(value)}"
    )
  end

  defp validate_type(:mod_arg, _key, {mod, _arg} = value) when is_atom(mod) do
    {:ok, value}
  end

  defp validate_type(:mod_arg, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected tuple {mod, arg}, got: #{inspect(value)}"
    )
  end

  defp validate_type({:fun, arity}, key, value) do
    if is_function(value) do
      case :erlang.fun_info(value, :arity) do
        {:arity, ^arity} ->
          {:ok, value}

        {:arity, fun_arity} ->
          error_tuple(
            key,
            value,
            "invalid value for #{render_key(key)}: expected function of arity #{arity}, got: function of arity #{inspect(fun_arity)}"
          )
      end
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected function of arity #{arity}, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(nil, key, value) do
    if is_nil(value) do
      {:ok, value}
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected nil, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type({:custom, mod, fun, args}, key, value) do
    case apply(mod, fun, [value | args]) do
      {:ok, value} ->
        {:ok, value}

      {:error, message} when is_binary(message) ->
        error_tuple(key, value, "invalid value for #{render_key(key)}: " <> message)

      other ->
        raise "custom validation function #{inspect(mod)}.#{fun}/#{length(args) + 1} " <>
                "must return {:ok, value} or {:error, message}, got: #{inspect(other)}"
    end
  end

  defp validate_type({:in, choices}, key, value) do
    if value in choices do
      {:ok, value}
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected one of #{inspect(choices)}, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type({:or, subtypes}, key, value) do
    result =
      Enum.reduce_while(subtypes, _errors = [], fn subtype, errors_acc ->
        {subtype, nested_schema} =
          case subtype do
            {type, keys} when type in [:keyword_list, :non_empty_keyword_list, :map] ->
              {type, keys}

            other ->
              {other, _nested_schema = nil}
          end

        case validate_type(subtype, key, value) do
          {:ok, value} when not is_nil(nested_schema) ->
            case validate_options_with_schema_and_path(value, nested_schema, _path = [key]) do
              {:ok, value} -> {:halt, {:ok, value}}
              {:error, %ValidationError{} = error} -> {:cont, [error | errors_acc]}
            end

          {:ok, value} ->
            {:halt, {:ok, value}}

          {:error, %ValidationError{} = reason} ->
            {:cont, [reason | errors_acc]}
        end
      end)

    case result do
      {:ok, value} ->
        {:ok, value}

      errors when is_list(errors) ->
        message =
          "expected #{render_key(key)} to match at least one given type, but didn't match " <>
            "any. Here are the reasons why it didn't match each of the allowed types:\n\n" <>
            Enum.map_join(errors, "\n", &("  * " <> Exception.message(&1)))

        error_tuple(key, value, message)
    end
  end

  defp validate_type({:list, subtype}, key, value) when is_list(value) do
    {subtype, nested_schema} =
      case subtype do
        {type, keys} when type in [:keyword_list, :non_empty_keyword_list, :map] ->
          {type, keys}

        other ->
          {other, _nested_schema = nil}
      end

    updated_elements =
      for {elem, index} <- Stream.with_index(value) do
        case validate_type(subtype, {__MODULE__, :list, index}, elem) do
          {:ok, value} when not is_nil(nested_schema) ->
            case validate_options_with_schema_and_path(value, nested_schema, _path = [key]) do
              {:ok, updated_value} -> updated_value
              {:error, %ValidationError{} = error} -> throw({:error, index, error})
            end

          {:ok, updated_elem} ->
            updated_elem

          {:error, %ValidationError{} = error} ->
            throw({:error, error})
        end
      end

    {:ok, updated_elements}
  catch
    {:error, %ValidationError{} = error} ->
      error_tuple(key, value, "invalid list in #{render_key(key)}: #{error.message}")

    {:error, index, %ValidationError{} = error} ->
      error_tuple(
        key,
        value,
        "invalid list element at position #{index} in #{render_key(key)}: #{error.message}"
      )
  end

  defp validate_type({:list, _subtype}, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected list, got: #{inspect(value)}"
    )
  end

  defp validate_type({:tuple, tuple_def}, key, value)
       when is_tuple(value) and length(tuple_def) == tuple_size(value) do
    tuple_def
    |> Stream.with_index()
    |> Enum.reduce_while([], fn {subtype, index}, acc ->
      elem = elem(value, index)

      case validate_type(subtype, {__MODULE__, :tuple, index}, elem) do
        {:ok, updated_elem} -> {:cont, [updated_elem | acc]}
        {:error, %ValidationError{} = error} -> {:halt, error}
      end
    end)
    |> case do
      acc when is_list(acc) ->
        {:ok, acc |> Enum.reverse() |> List.to_tuple()}

      %ValidationError{} = error ->
        error_tuple(key, value, "invalid tuple in #{render_key(key)}: #{error.message}")
    end
  end

  defp validate_type({:tuple, tuple_def}, key, value) when is_tuple(value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected tuple with #{length(tuple_def)} elements, got: #{inspect(value)}"
    )
  end

  defp validate_type({:tuple, _tuple_def}, key, value) do
    error_tuple(
      key,
      value,
      "invalid value for #{render_key(key)}: expected tuple, got: #{inspect(value)}"
    )
  end

  defp validate_type({:struct, struct_name}, key, value) do
    if match?(%^struct_name{}, value) do
      {:ok, value}
    else
      error_tuple(
        key,
        value,
        "invalid value for #{render_key(key)}: expected #{inspect(struct_name)}, got: #{inspect(value)}"
      )
    end
  end

  defp validate_type(_type, _key, value) do
    {:ok, value}
  end

  defp keyword_list?(value) do
    is_list(value) and Enum.all?(value, &match?({key, _value} when is_atom(key), &1))
  end

  defp expand_star_to_option_keys(keys, opts) do
    case keys[:*] do
      nil ->
        keys

      schema_opts ->
        Enum.map(opts, fn {k, _} -> {k, schema_opts} end)
    end
  end

  defp available_types() do
    types =
      Enum.map(@basic_types, &inspect/1) ++
        [
          "{:fun, arity}",
          "{:in, choices}",
          "{:or, subtypes}",
          "{:custom, mod, fun, args}",
          "{:list, subtype}",
          "{:tuple, list_of_subtypes}",
          "{:map, key_type, value_type}",
          "{:struct, struct_name}"
        ]

    Enum.join(types, ", ")
  end

  @doc false
  def validate_type(value) when value in @basic_types do
    {:ok, value}
  end

  def validate_type({:fun, arity} = value) when is_integer(arity) and arity >= 0 do
    {:ok, value}
  end

  # "choices" here can be any enumerable so there's no easy and fast way to validate it.
  def validate_type({:in, _choices} = value) do
    {:ok, value}
  end

  def validate_type({:custom, mod, fun, args} = value)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    {:ok, value}
  end

  def validate_type({:or, subtypes} = value) when is_list(subtypes) do
    Enum.reduce_while(subtypes, {:ok, value}, fn
      {type, _keys}, acc
      when type in [:keyword_list, :non_empty_keyword_list, :map] ->
        {:cont, acc}

      subtype, acc ->
        case validate_type(subtype) do
          {:ok, _value} -> {:cont, acc}
          {:error, reason} -> {:halt, {:error, "invalid type given to :or type: #{reason}"}}
        end
    end)
  end

  # This is to support the special-cased "{:list, {:keyword_list, my_key: [type: ...]}}",
  # like we do in the :or type.
  def validate_type({:list, {type, keys}})
      when type in [:keyword_list, :non_empty_keyword_list, :map] and is_list(keys) do
    {:ok, {:list, {type, keys}}}
  end

  def validate_type({:list, subtype}) do
    case validate_type(subtype) do
      {:ok, validated_subtype} -> {:ok, {:list, validated_subtype}}
      {:error, reason} -> {:error, "invalid subtype given to :list type: #{reason}"}
    end
  end

  def validate_type({:tuple, tuple_def}) when is_list(tuple_def) do
    validated_def =
      Enum.map(tuple_def, fn subtype ->
        case validate_type(subtype) do
          {:ok, validated_subtype} -> validated_subtype
          {:error, reason} -> throw({:error, "invalid subtype given to :tuple type: #{reason}"})
        end
      end)

    {:ok, {:tuple, validated_def}}
  catch
    {:error, reason} -> {:error, reason}
  end

  def validate_type({:map, key_type, value_type}) do
    valid_key_type =
      case validate_type(key_type) do
        {:ok, validated_key_type} -> validated_key_type
        {:error, reason} -> throw({:error, "invalid key_type for :map type: #{reason}"})
      end

    valid_values_type =
      case validate_type(value_type) do
        {:ok, validated_values_type} -> validated_values_type
        {:error, reason} -> throw({:error, "invalid value_type for :map type: #{reason}"})
      end

    {:ok, {:map, valid_key_type, valid_values_type}}
  catch
    {:error, reason} -> {:error, reason}
  end

  def validate_type({:struct, struct_name}) when is_atom(struct_name) do
    {:ok, {:struct, struct_name}}
  end

  def validate_type({:struct, struct_name}) do
    {:error, "invalid struct_name for :struct, expected atom, got #{inspect(struct_name)}"}
  end

  def validate_type(value) do
    {:error, "unknown type #{inspect(value)}.\n\nAvailable types: #{available_types()}"}
  end

  defp error_tuple(key, value, message) do
    {:error, %ValidationError{key: key, message: message, value: value}}
  end

  defp render_key({__MODULE__, :key}), do: "map key"
  defp render_key({__MODULE__, :value, key}), do: "map key #{inspect(key)}"
  defp render_key({__MODULE__, :tuple, index}), do: "tuple element at position #{index}"
  defp render_key({__MODULE__, :list, index}), do: "list element at position #{index}"
  defp render_key(key), do: inspect(key) <> " option"
end
