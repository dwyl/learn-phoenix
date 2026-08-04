defmodule Phoenix.HTML.FormField do
  @moduledoc """
  The struct returned by `form[field]`.

  It has the following fields:

    * `:errors` - a list of errors belonging to the field
    * `:field` - the field name as an atom or a string
    * `:form` - the parent `form` struct
    * `:id` - the `id` to be used as form input as a string
    * `:name` - the `name` to be used as form input as a string
    * `:value` - the value for the input

  """
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          errors: [term],
          field: Phoenix.HTML.Form.field(),
          form: Phoenix.HTML.Form.t(),
          value: term
        }

  @enforce_keys [:id, :name, :errors, :field, :form, :value]
  defstruct [:id, :name, :errors, :field, :form, :value]
end
