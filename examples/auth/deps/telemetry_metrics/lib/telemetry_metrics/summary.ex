defmodule Telemetry.Metrics.Summary do
  @moduledoc """
  Defines a specification of summary metric.
  """

  alias Telemetry.Metrics

  defstruct [
    :name,
    :event_name,
    :measurement,
    :tags,
    :tag_values,
    :keep,
    :description,
    :unit,
    :reporter_options
  ]

  @type t :: %__MODULE__{
          name: Metrics.normalized_metric_name(),
          event_name: :telemetry.event_name(),
          measurement: Metrics.measurement(),
          tags: Metrics.tags(),
          tag_values: Metrics.tag_values(),
          keep: Metrics.keep(),
          description: Metrics.description(),
          unit: Metrics.unit(),
          reporter_options: Metrics.reporter_options()
        }
end
