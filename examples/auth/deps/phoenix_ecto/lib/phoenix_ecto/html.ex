if Code.ensure_loaded?(Phoenix.HTML) do
  defimpl Phoenix.HTML.FormData, for: Ecto.Changeset do
    def to_form(changeset, opts) do
      %{params: params, data: data, action: action} = changeset
      {action, opts} = Keyword.pop(opts, :action, action)
      {name, opts} = Keyword.pop(opts, :as)

      name = to_string(name || form_for_name(data))
      id = Keyword.get(opts, :id) || name

      %Phoenix.HTML.Form{
        source: changeset,
        impl: __MODULE__,
        id: id,
        action: action,
        name: name,
        errors: form_for_errors(changeset, action),
        data: data,
        params: params || %{},
        hidden: form_for_hidden(data),
        options: Keyword.put_new(opts, :method, form_for_method(data))
      }
    end

    def to_form(source, %{action: parent_action} = form, field, opts) do
      if Keyword.has_key?(opts, :default) do
        raise ArgumentError,
              ":default is not supported on inputs_for with changesets. " <>
                "The default value must be set in the changeset data"
      end

      {prepend, opts} = Keyword.pop(opts, :prepend, [])
      {append, opts} = Keyword.pop(opts, :append, [])
      {name, opts} = Keyword.pop(opts, :as)
      {id, opts} = Keyword.pop(opts, :id)

      id = to_string(id || form.id <> "_#{field}")
      name = to_string(name || form.name <> "[#{field}]")

      case find_inputs_for_type!(source, field) do
        {:one, cast, module} ->
          changesets =
            case Map.fetch(source.changes, field) do
              {:ok, nil} ->
                []

              {:ok, map} ->
                [validate_map!(map, field)]

              _ ->
                [validate_map!(assoc_from_data(source.data, field), field) || module.__struct__()]
            end

          for changeset <- skip_replaced(changesets) do
            %{data: data, params: params} =
              changeset = to_changeset(changeset, parent_action, module, cast, nil)

            %Phoenix.HTML.Form{
              source: changeset,
              action: parent_action,
              impl: __MODULE__,
              id: id,
              name: name,
              errors: form_for_errors(changeset, parent_action),
              data: data,
              params: params || %{},
              hidden: form_for_hidden(data),
              options: opts
            }
          end

        {:many, cast, module} ->
          changesets =
            validate_list!(Map.get(source.changes, field), field) ||
              validate_list!(assoc_from_data(source.data, field), field) || []

          changesets =
            if form.params[Atom.to_string(field)] do
              changesets
            else
              prepend ++ changesets ++ append
            end

          changesets = skip_replaced(changesets)

          for {changeset, index} <- Enum.with_index(changesets) do
            %{data: data, params: params} =
              changeset = to_changeset(changeset, parent_action, module, cast, index)

            index_string = Integer.to_string(index)

            %Phoenix.HTML.Form{
              source: changeset,
              impl: __MODULE__,
              action: parent_action,
              id: id <> "_" <> index_string,
              name: name <> "[" <> index_string <> "]",
              index: index,
              errors: form_for_errors(changeset, parent_action),
              data: data,
              params: params || %{},
              hidden: form_for_hidden(data),
              options: opts
            }
          end
      end
    end

    def input_value(%{changes: changes, data: data}, %{params: params}, field)
        when is_atom(field) do
      case changes do
        %{^field => value} ->
          value

        %{} ->
          string = Atom.to_string(field)

          case params do
            %{^string => value} -> value
            %{} -> Map.get(data, field)
          end
      end
    end

    def input_value(_data, _form, field) do
      raise ArgumentError, "expected field to be an atom, got: #{inspect(field)}"
    end

    def input_type(%{types: types}, _, field) do
      type = Map.get(types, field, :string)
      type = if Ecto.Type.primitive?(type), do: type, else: type.type()

      case type do
        :integer -> :number_input
        :boolean -> :checkbox
        :date -> :date_select
        :time -> :time_select
        :utc_datetime -> :datetime_select
        :naive_datetime -> :datetime_select
        _ -> :text_input
      end
    end

    def input_validations(%{required: required, validations: validations} = changeset, _, field) do
      [required: field in required] ++
        for {key, validation} <- validations,
            key == field,
            attr <- validation_to_attrs(validation, field, changeset),
            do: attr
    end

    defp assoc_from_data(data, field) do
      assoc_from_data(data, Map.fetch!(data, field), field)
    end

    defp assoc_from_data(%{__meta__: %{state: :built}}, %Ecto.Association.NotLoaded{}, _field) do
      nil
    end

    defp assoc_from_data(%{__struct__: struct}, %Ecto.Association.NotLoaded{}, field) do
      raise ArgumentError,
            "using inputs_for for association `#{field}` " <>
              "from `#{inspect(struct)}` but it was not loaded. Please preload your " <>
              "associations before using them in inputs_for"
    end

    defp assoc_from_data(_data, value, _field) do
      value
    end

    defp skip_replaced(changesets) do
      Enum.reject(changesets, fn
        %Ecto.Changeset{action: :replace} -> true
        _ -> false
      end)
    end

    defp validation_to_attrs({:length, opts}, _field, _changeset) do
      max =
        if val = Keyword.get(opts, :max) do
          [maxlength: val]
        else
          []
        end

      min =
        if val = Keyword.get(opts, :min) do
          [minlength: val]
        else
          []
        end

      max ++ min
    end

    defp validation_to_attrs({:number, opts}, field, changeset) do
      type = Map.get(changeset.types, field, :integer)
      step_for(type) ++ min_for(type, opts) ++ max_for(type, opts)
    end

    defp validation_to_attrs(_validation, _field, _changeset) do
      []
    end

    defp step_for(:integer), do: [step: 1]
    defp step_for(_other), do: [step: "any"]

    defp max_for(type, opts) do
      cond do
        max = type == :integer && Keyword.get(opts, :less_than) -> [max: max - 1]
        max = Keyword.get(opts, :less_than_or_equal_to) -> [max: max]
        true -> []
      end
    end

    defp min_for(type, opts) do
      cond do
        min = type == :integer && Keyword.get(opts, :greater_than) -> [min: min + 1]
        min = Keyword.get(opts, :greater_than_or_equal_to) -> [min: min]
        true -> []
      end
    end

    defp find_inputs_for_type!(changeset, field) do
      case Map.fetch(changeset.types, field) do
        {:ok, {tag, %{cardinality: cardinality, on_cast: cast, related: module}}}
        when tag in [:embed, :assoc] ->
          {cardinality, cast, module}

        _ ->
          struct = changeset.data.__struct__

          raise ArgumentError,
                "could not generate inputs for #{inspect(field)} from #{inspect(struct)}. " <>
                  "Check the field exists and it is one of embeds_one, embeds_many, has_one, " <>
                  "has_many, belongs_to or many_to_many"
      end
    end

    defp to_changeset(%Ecto.Changeset{} = changeset, parent_action, _module, _cast, _index),
      do: apply_action(changeset, parent_action)

    defp to_changeset(%{} = data, parent_action, _module, cast, _index) when is_function(cast, 2),
      do: apply_action(cast!(cast, data), parent_action)

    defp to_changeset(%{} = data, parent_action, _module, cast, index) when is_function(cast, 3),
      do: apply_action(cast!(cast, data, index), parent_action)

    defp to_changeset(%{} = data, parent_action, _module, {module, func, arguments} = mfa, _index)
         when is_atom(module) and is_atom(func) and is_list(arguments),
         do: apply_action(apply!(mfa, data), parent_action)

    defp to_changeset(%{} = data, parent_action, _module, nil, _index),
      do: apply_action(Ecto.Changeset.change(data), parent_action)

    defp cast!(cast, data) do
      case cast.(data, %{}) do
        %Ecto.Changeset{} = changeset ->
          changeset

        other ->
          raise "expected on_cast/2 callback #{inspect(cast)} to return an Ecto.Changeset, " <>
                  "got: #{inspect(other)}"
      end
    end

    defp cast!(cast, data, index) do
      case cast.(data, %{}, index) do
        %Ecto.Changeset{} = changeset ->
          changeset

        other ->
          raise "expected on_cast/3 callback #{inspect(cast)} to return an Ecto.Changeset, " <>
                  "got: #{inspect(other)}"
      end
    end

    defp apply!({module, func, arguments}, data) do
      case apply(module, func, [data, %{} | arguments]) do
        %Ecto.Changeset{} = changeset ->
          changeset

        other ->
          raise "expected #{module}.#{func} to return an Ecto.Changeset, " <>
                  "got: #{inspect(other)}"
      end
    end

    # If the parent changeset had no action, we need to remove the action
    # from children changeset so we ignore all errors accordingly.
    defp apply_action(changeset, nil),
      do: %{changeset | action: nil}

    defp apply_action(changeset, _action),
      do: changeset

    defp validate_list!(value, _what) when is_list(value) or is_nil(value), do: value

    defp validate_list!(value, what) do
      raise ArgumentError, "expected #{what} to be a list, got: #{inspect(value)}"
    end

    defp validate_map!(value, _what) when is_map(value) or is_nil(value), do: value

    defp validate_map!(value, what) do
      raise ArgumentError, "expected #{what} to be a map/struct, got: #{inspect(value)}"
    end

    defp form_for_errors(_changeset, nil = _action), do: []
    defp form_for_errors(_changeset, :ignore = _action), do: []
    defp form_for_errors(%Ecto.Changeset{errors: errors}, _action), do: errors

    defp form_for_hidden(%{__struct__: module} = data) do
      module.__schema__(:primary_key)
    rescue
      _ -> []
    else
      keys -> for k <- keys, v = Map.fetch!(data, k), do: {k, v}
    end

    defp form_for_hidden(_), do: []

    defp form_for_name(%{__struct__: module}) do
      module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end

    defp form_for_name(_) do
      raise ArgumentError,
            "cannot generate name for changeset where the data is not backed by a struct. " <>
              "You must either pass the :as option to form/form_for or use a struct-based changeset"
    end

    defp form_for_method(%{__meta__: %{state: :loaded}}), do: "put"
    defp form_for_method(_), do: "post"
  end

  defimpl Phoenix.HTML.Safe, for: Decimal do
    def to_iodata(t) do
      @for.to_string(t, :normal)
    end
  end
end
