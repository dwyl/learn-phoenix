defmodule Telemetry.Metrics.ConsoleReporter do
  @moduledoc """
  A reporter that prints events and metrics to the terminal.

  This is useful for debugging and discovering all available
  measurements and metadata in an event.

  For example, imagine the given metrics:

      metrics = [
        last_value("vm.memory.binary", unit: :byte),
        counter("vm.memory.total")
      ]

  A console reporter can be started as a child of your supervision tree as:

      {Telemetry.Metrics.ConsoleReporter, metrics: metrics}

  Now when the "vm.memory" telemetry event is dispatched, we will see
  reports like this:

      [Telemetry.Metrics.ConsoleReporter] Got new event!
      Event name: vm.memory
      All measurements: %{binary: 100, total: 200}
      All metadata: %{}

      Metric measurement: :binary (last_value)
      With value: 100 byte
      And tag values: %{}

      Metric measurement: :total (counter)
      With value: 200
      And tag values: %{}

  In other words, every time there is an event for any of the registered
  metrics, it prints the event measurement and metadata, and then it prints
  information about each metric to the user.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    server_opts = Keyword.take(opts, [:name])
    device = opts[:device] || :stdio

    metrics =
      opts[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    GenServer.start_link(__MODULE__, {metrics, device}, server_opts)
  end

  @impl true
  def init({metrics, device}) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &__MODULE__.handle_event/4, {metrics, device})
    end

    {:ok, Map.keys(groups)}
  end

  @impl true
  def terminate(_, events) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  @doc false
  def handle_event(event_name, measurements, metadata, {metrics, device}) do
    prelude = """
    [#{inspect(__MODULE__)}] Got new event!
    Event name: #{Enum.join(event_name, ".")}
    All measurements: #{inspect(measurements)}
    All metadata: #{inspect(metadata)}
    """

    parts =
      for %struct{} = metric <- metrics do
        header = """

        Metric measurement: #{measurement_name(metric)} (#{metric(struct)})
        """

        [
          header
          | try do
              measurement = extract_measurement(metric, measurements, metadata)
              tags = extract_tags(metric, metadata)

              cond do
                is_nil(measurement) ->
                  """
                  Measurement value missing (metric skipped)
                  """

                not keep?(metric, metadata, measurements) ->
                  """
                  Event dropped
                  """

                metric.__struct__ == Telemetry.Metrics.Counter ->
                  """
                  Tag values: #{inspect(tags)}
                  """

                true ->
                  """
                  With value: #{inspect(measurement)}#{unit(metric.unit)}#{info(measurement)}
                  Tag values: #{inspect(tags)}
                  """
              end
            rescue
              e ->
                Logger.error([
                  "Could not format metric #{inspect(metric)}\n",
                  Exception.format(:error, e, __STACKTRACE__)
                ])

                """
                Errored when processing (metric skipped - handler may detach!)
                """
            end
        ]
      end

    IO.puts(device, [prelude | parts])
  end

  defp measurement_name(%{measurement: measurement}) when is_atom(measurement),
    do: inspect(measurement)

  defp measurement_name(%{measurement: fun, name: name}) when is_function(fun) do
    measurement = List.last(name)

    "#{inspect(measurement)} [via #{inspect(fun)}]"
  end

  defp keep?(metric, metadata, measurements) do
    case metric do
      %{keep: nil} -> true
      %{keep: keep} when is_function(keep, 1) -> keep.(metadata)
      %{keep: keep} when is_function(keep, 2) -> keep.(metadata, measurements)
    end
  end

  defp extract_measurement(metric, measurements, metadata) do
    case metric.measurement do
      fun when is_function(fun, 2) -> fun.(measurements, metadata)
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end

  defp info(int) when is_number(int), do: ""
  defp info(_), do: " (WARNING! measurement should be a number)"

  defp unit(:unit), do: ""
  defp unit(unit), do: " #{unit}"

  defp metric(Telemetry.Metrics.Counter), do: "counter"
  defp metric(Telemetry.Metrics.Distribution), do: "distribution"
  defp metric(Telemetry.Metrics.LastValue), do: "last_value"
  defp metric(Telemetry.Metrics.Sum), do: "sum"
  defp metric(Telemetry.Metrics.Summary), do: "summary"

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end
end
