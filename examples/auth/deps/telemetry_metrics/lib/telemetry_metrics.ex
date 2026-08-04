defmodule Telemetry.Metrics do
  @moduledoc """
  Common interface for defining metrics based on
  [`:telemetry`](https://github.com/beam-telemetry/telemetry) events.

  Metrics are aggregations of Telemetry events with specific names, providing
  a view of the system's behaviour over time.

  To give a more concrete example, imagine that somewhere in your code there is
  a function which sends an HTTP request, measures the time it took to get a
  response, and emits an event with the information:

      :telemetry.execute([:http, :request, :stop], %{duration: duration})

  You could define a counter metric, which counts how many HTTP requests were
  completed:

      Telemetry.Metrics.counter("http.request.stop.duration")

  or you could use a summary metric to see statistics about the request duration:

      Telemetry.Metrics.summary("http.request.stop.duration")

  This documentation is going to cover all the available metrics and how to use
  them, as well as options, and how to integrate those metrics with reporters.

  ## Metrics

  There are five metric types provided by `Telemetry.Metrics`:

    * `counter/2` which counts the total number of emitted events
    * `sum/2` which keeps track of the sum of selected measurement
    * `last_value/2` holding the value of the selected measurement from
      the most recent event
    * `summary/2` calculating statistics of the selected measurement,
      like maximum, mean, percentiles etc.
    * `distribution/2` which builds a histogram of selected measurement

  The first argument to all metric functions is the metric name. Metric
  name can be provided as a string (e.g. `"http.request.stop.duration"`) or a
  list of atoms (`[:http, :request, :stop, :duration]`). The metric name is
  automatically used to infer the telemetry event and measurement. For example,
  In the `"http.request.stop.duration"` example, the source event name is
  `[:http, :request, :stop]` and metric values are drawn from `:duration`
  measurement. Like this:

      [:http , :request, :stop]      :duration
      <----- event name ------> <-- measurement -->

  You can also explicitly specify the event name and measurement
  if you prefer.

  The second argument is a list of options. Below is the description of the
  options common to all metric types:

    * `:event_name` - the source event name. Can be represented either as a
      string (e.g. `"http.request"`) or a list of atoms (`[:http, :request]`).
      By default the event name is all but the last segment of the metric name.
    * `:measurement` - the event measurement used as a source of a metric values.
      By default it is the last segment of the metric name. It can be:
      * a key in the event's measurements map
      * an unary function accepting the whole measurements map and returning the
        actual value to be used.
      * a binary function accepting the measurements and metadata maps and
        returning the actual value to be used.
    * `:tags` - a subset of metadata keys by which aggregations will be broken down.
      Defaults to an empty list.
    * `:tag_values` - a function that receives the metadata and returns a map with
      the tags as keys and their respective values. Defaults to returning the
      metadata itself.
    * `:keep` - a predicate function that evaluates the metadata and measurement
      to conditionally record a given event. `:keep` and `:drop` cannot be
      combined. Defaults to `nil`.
    * `:drop` - a predicate function that evaluates the metadata and measurement
      to conditionally skip recording a given event. `:keep` and `:drop` cannot
      be combined. Defaults to `nil`.
    * `:description` - human-readable description of the metric. Might be used by
      reporters for documentation purposes. Defaults to `nil`.
    * `:unit` - an atom describing the unit of selected measurement, typically in
      singular, such as `:millisecond`, `:byte`, `:kilobyte`, etc. It may also be
      a tuple indicating that a measurement should be converted from one unit to
      another before a metric is updated. Currently, only time and byte unit
      conversions are supported. We discuss those in detail in the "Converting Units"
      section.
    * `:reporter_options` - a keyword list of reporter-specific options for the metric.

  ## Breaking down metric values by tags

  Sometimes it's not enough to have a global overview of all HTTP requests received
  or all DB queries made. It's often more helpful to break down this data, for example,
  we might want to have separate metric values for each unique database table and
  operation name (`select`, `insert` etc.) to see how these particular queries behave.

  This is where tagging comes into play. All metric definitions accept a `:tags` option:

      counter("db.query.duration", tags: [:table, :operation])

  The above definition means that we want to keep track of the number of queries, but
  we want a separate counter for each unique pair of table and operation. Tag values are
  fetched from event metadata - this means that in this example, `[:db, :query]` events
  need to include `:table` and `:operation` keys in their payload:

      :telemetry.execute([:db, :query], %{duration: 198}, %{table: "users", operation: "insert"})
      :telemetry.execute([:db, :query], %{duration: 112}, %{table: "users", operation: "select"})
      :telemetry.execute([:db, :query], %{duration: 201}, %{table: "sessions", operation: "insert"})
      :telemetry.execute([:db, :query], %{duration: 212}, %{table: "sessions", operation: "insert"})

  The result of aggregating the events above looks like this:

  | table    | operation | count |
  | -------- | --------- | ----- |
  | users    | insert    | 1     |
  | users    | select    | 1     |
  | sessions | insert    | 2     |

  The approach where we create a separate metric for some unique set of properties
  is called a multi-dimensional data model.

  ### Transforming event metadata for tagging

  Finally, sometimes there is a need to modify event metadata before it's used for
  tagging. Each metric definition accepts a function in `:tag_values` option which
  transforms the metadata into desired shape. Note that this function is called for
  each event, so it's important to keep it fast if the rate of events is high.

  ## Converting Units

  It might happen that the unit of measurement we're tracking is not the desirable unit
  for the metric values, e.g. events are emitted by a 3rd-party library we do not control,
  or a reporter we're using requires specific unit of measurement.

  For these scenarios, each metric definition accepts a `:unit` option in a form of a tuple:

      summary("http.request.stop.duration", unit: {from_unit, to_unit})

  This means that the measurement will be converted from `from_unit` to `to_unit` before
  being used for updating the metric. Currently, only time and byte conversions are
  supported.

  ### Time Conversions

  Most time measurements in the Erlang VM are done in the `:native` unit, which we need
  to convert to the desired precision. The supported time units are: `:second`, `:millisecond`,
  `:microsecond`, `:nanosecond` and `:native`.

  For example, to convert HTTP request duration from `:native` time unit to milliseconds
  you'd write:

      summary("http.request.stop.duration", unit: {:native, :millisecond})

  ### Byte Conversions

  Some metrics, like VM memory's usage are reported in bytes. You might want to convert this
  to megabytes, for example. The supported byte units are: `:byte`, `:kilobyte` and `:megabyte`.

  In order to convert a metric value from bytes to megabytes, you can write the following:

      last_value("vm.memory.total", unit: {:byte, :megabyte})

  ## VM metrics

  `Telemetry.Metrics` doesn't have a special treatment for the VM metrics - they need
  to be based on the events like all other metrics.

  `:telemetry_poller` package (http://hexdocs.pm/telemetry_poller) exposes a bunch of
  VM-related metrics and also provides custom periodic measurements. You can add
  telemetry poller as a dependency:

      {:telemetry_poller, "~> 0.4"}

  By simply adding `:telemetry_poller` as a dependency, two events will become available:

    * `[:vm, :memory]` - contains the total memory, as well as the memory used for
      binaries, processes, etc. See `erlang:memory/0` for all keys;
    * `[:vm, :total_run_queue_lengths]` - returns the run queue lengths for CPU and
      IO schedulers. It contains the `total`, `cpu` and `io` measurements;

  You can consume those events with `Telemetry.Metrics` with the following sample metrics:

      last_value("vm.memory.total", unit: :byte)
      last_value("vm.total_run_queue_lengths.total")
      last_value("vm.total_run_queue_lengths.cpu")
      last_value("vm.total_run_queue_lengths.io")

  If you want to change the frequency of those measurements, you can set the
  following configuration in your config file:

      config :telemetry_poller, :default, period: 5_000 # the default

  Or disable it completely with:

      config :telemetry_poller, :default, false

  The `:telemetry_poller` package also allows you to run your own poller, which is
  useful to retrieve process information or perform custom measurements periodically.
  For example, to keep track of the number of users, inside a supervision tree, you could do:

      measurements = [
        {:process_info,
         event: [:my_app, :worker],
         name: MyApp.Worker,
         keys: [:message_queue_len, :memory]},

        {MyApp, :measure_users, []}
      ]

      Supervisor.start_link([
        # Run the given measurements every 10 seconds
        {:telemetry_poller, measurements: measurements(), period: 10_000}
      ], strategy: :one_for_one)

  Where `MyApp.measure_users/0` could be written like this:

      defmodule MyApp do
        def measure_users do
          :telemetry.execute([:my_app, :users], %{total: MyApp.users_count()}, %{})
        end
      end

  Now with measurements in place, you can define the metrics for the
  events above:

      last_value("my_app.worker.memory", unit: :byte)
      last_value("my_app.worker.message_queue_len")
      last_value("my_app.users.total")

  ## Optionally Recording Metric Events

  There may be occasions where you want to record metrics differently or not at all based
  upon metadata. Rather than depending on changing event names with prefixes, you can instead
  provide a predicate function which returns true when you want the metric to be
  processed for this event and false when you do not.

  Let's examine some a few examples where optional recording can be helpful.

  ### Filtering on Metadata

  Let's assume you are using an HTTP client library in your application which has the following
  event_name: `[:http_client, :request, :stop]`. You use this library in multiple places and
  you'd like to monitor the request duration.

  You can use the event provided by the library but you have very different acceptable
  performance requirements for a critical request, so it would be better to provide a different
  metric name for monitoring. The client library includes a user configured `:name` option which
  you can set and is passed in the event metadata.

  Let's create a default distribution metric and one for the high performance call.

      distribution(
        "http.client.request.duration",
        event_name: [:http_client, :request, :stop],
        drop: &(match?(%{name: :fast_client}, &1))
      )

      distribution(
        "http.fast.client.request.duration",
        event_name: [:http_client, :request, :stop],
        keep: &(match?(%{name: :fast_client}, &1))
      )

  With this configuration, you can now monitor these requests separately. In the first example,
  any events where the client's name is `:fast_client` will be dropped for that metric.
  Conversely, any matching events in the second example metric will be kept.

  Note: only `:keep` OR `:drop` may be set, never both.

  ### Other Uses

  Another potential use case for `:keep | :drop` could be per metric sampling rates. As long
  as your function returns a boolean, it can determine if the event should be processed.

  ### Reporter Support

  Event optional recording must be supported by the reporter you are using. Check your reporter's
  documentation before relying on this functionality.

  The `keep` function should be evaluated by reporters _prior_ to `tag_values` using the
  raw `:telemetry.metadata()` values from the event.

  ## Reporters

  So far, we have talked about metrics and how to describe them, but we haven't discussed
  how those metrics are consumed and published to a system that provides data visualization,
  aggregation, and more. The job of subscribing to events and processing the actual metrics
  is a responsibility of reporters.

  Generally speaking, a reporter is a process that you would start in your supervision
  tree with a list of metrics as input. For example, `Telemetry.Metrics` ships with a
  `Telemetry.Metrics.ConsoleReporter` module, which prints data to the terminal as an
  example. You would start it as follows:

      metrics = [
        last_value("my_app.worker.memory", unit: :byte),
        last_value("my_app.worker.message_queue_len"),
        last_value("my_app.users.total")
      ]

      Supervisor.start_link([
        {Telemetry.Metrics.ConsoleReporter, metrics: metrics}
      ], strategy: :one_for_one)

  Reporters take metric definitions as an input, subscribe to relevant events and
  aggregate data when the events are emitted. Reporters may push metrics to StatsD,
  some time-series database, or exposing a HTTP endpoint for Prometheus to scrape.
  In a nutshell, `Telemetry.Metrics` defines only how metrics of particular type
  should behave and reporters provide the actual implementation for these aggregations.

  Official reporters, maintained by the Observability Working Group of the Erlang
  Ecosystem Foundation, can be found on the [BEAM Telemetry organization on GitHub](https://github.com/beam-telemetry/).
  You may also [find community reporters on hex.pm](https://hex.pm/packages?search=telemetry_metrics).
  You can also read the [Writing Reporters](writing_reporters.html) page for general
  information on how to write a reporter.

  ## Wiring it all up

  Over the previous sections we discussed how to setup metrics and pass them to reporters
  and how to configure a poller for measurements. We can wire it all up into a single
  module as shown below. The example below would be used in the context of a Phoenix
  application, where we have web metrics, database metrics (through Ecto) as well as
  from the database, Phoenix metrics as well as VM metrics.

  The first step is to add both `:telemetry_metrics` and `:telemetry_poller` as
  dependencies:

      [
        {:telemetry_poller, "~> 0.4"},
        {:telemetry_metrics, "~> 0.4"}
      ]

  Then you could define a module that wires everything up:

      defmodule MyAppWeb.Telemetry do
        use Supervisor
        import Telemetry.Metrics

        def start_link(arg) do
          Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
        end

        def init(_arg) do
          children = [
            {:telemetry_poller,
             measurements: periodic_measurements(),
             period: 10_000},
            # Or TelemetryMetricsPrometheus or TelemetryMetricsFooBar
            {TelemetryMetricsStatsd, metrics: metrics()}
          ]

          Supervisor.init(children, strategy: :one_for_one)
        end

        defp metrics do
          [
            # VM Metrics
            last_value("vm.memory.total", unit: :byte),
            last_value("vm.total_run_queue_lengths.total"),
            last_value("vm.total_run_queue_lengths.cpu"),
            last_value("vm.total_run_queue_lengths.io"),

            last_value("my_app.worker.memory", unit: :byte),
            last_value("my_app.worker.message_queue_len"),

            # Database Time Metrics
            summary("my_app.repo.query.total_time", unit: {:native, :millisecond}),
            summary("my_app.repo.query.decode_time", unit: {:native, :millisecond}),
            summary("my_app.repo.query.query_time", unit: {:native, :millisecond}),
            summary("my_app.repo.query.idle_time", unit: {:native, :millisecond}),
            summary("my_app.repo.query.queue_time", unit: {:native, :millisecond}),

            # Phoenix Time Metrics
            summary("phoenix.endpoint.stop.duration",
                    unit: {:native, :millisecond}),
            summary(
              "phoenix.router_dispatch.stop.duration",
              unit: {:native, :millisecond},
              tags: [:plug]
            )
          ]
        end

        defp periodic_measurements do
          [
            {:process_info,
             event: [:my_app, :worker],
             name: Rumbl.Worker,
             keys: [:message_queue_len, :memory]}
          ]
        end
      end
  """

  require Logger

  alias Telemetry.Metrics.{Counter, Sum, LastValue, Summary, Distribution}

  @typedoc """
  The name of the metric, either as string or a list of atoms.
  """
  @type metric_name :: String.t() | normalized_metric_name()

  @typedoc """
  The name of the metric represented as a list of atoms.
  """
  @type normalized_metric_name :: [atom(), ...]

  @type measurement ::
          term()
          | (:telemetry.event_measurements() -> number())
          | (:telemetry.event_measurements(), :telemetry.event_metadata() -> number())
  @type tag :: term()
  @type tags :: [tag()]
  @type tag_values :: (:telemetry.event_metadata() -> :telemetry.event_metadata())
  @type predicate_fun ::
          (:telemetry.event_metadata() -> boolean())
          | (:telemetry.event_metadata(), :telemetry.event_measurements() -> boolean())
  @type keep :: predicate_fun()
  @type drop :: predicate_fun()
  @type description :: nil | String.t()
  @type unit :: atom()
  @type time_unit_conversion() :: {time_unit(), time_unit()}
  @type time_unit() :: :second | :millisecond | :microsecond | :nanosecond | :native
  @type byte_unit() :: :megabyte | :kilobyte | :byte
  @type byte_unit_conversion() :: {byte_unit(), byte_unit()}
  @type reporter_options :: keyword()
  @type metric_option ::
          {:event_name, String.t() | :telemetry.event_name()}
          | {:measurement, measurement()}
          | {:tags, tags()}
          | {:tag_values, tag_values()}
          | {:keep, keep()}
          | {:drop, drop()}
          | {:description, description()}
          | {:unit, unit() | time_unit_conversion() | byte_unit_conversion()}
          | {:reporter_options, reporter_options()}
  @type metric_options :: [metric_option()]

  @typedoc """
  One of the base metric definitions.
  """
  @type t() :: Counter.t() | LastValue.t() | Sum.t() | Summary.t() | Distribution.t()

  # API

  @doc """
  Returns a definition of counter metric.

  Counter metric keeps track of the total number of specific events emitted.

  The value of the counter is always incremented by one, regardless of the
  value of the measurement. However, note the measurement must still be
  available in the event, otherwise the event is not accounted for.

  See the ["Metrics"](#module-metrics) section in the top-level documentation of this module for more
  information.

  ## Example

      counter(
        "http.request.count",
        tags: [:controller, :action]
      )
  """
  @spec counter(metric_name(), metric_options()) :: Counter.t()
  def counter(metric_name, options \\ []) do
    struct(Counter, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of sum metric.

  Sum metric keeps track of the sum of selected measurement's values carried by specific events.

  See the ["Metrics"](#module-metrics) section in the top-level documentation of this module for more
  information.

  ## Example

      sum(
        "user.session_count",
        event_name: "user.session_count",
        measurement: :delta,
        tags: [:role]
      )
  """
  @spec sum(metric_name(), metric_options()) :: Sum.t()
  def sum(metric_name, options \\ []) do
    struct(Sum, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of last value metric.

  Last value keeps track of the selected measurement found in the most recent event.

  See the ["Metrics"](#module-metrics) section in the top-level documentation of this module for more
  information.

  ## Example

      last_value(
        "vm.memory.total",
        description: "Total amount of memory allocated by the Erlang VM", unit: :byte
      )
  """
  @spec last_value(metric_name(), metric_options()) :: LastValue.t()
  def last_value(metric_name, options \\ []) do
    struct(LastValue, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of summary metric.

  This metric aggregates measurement's values into statistics, e.g. minimum and maximum, mean, or
  percentiles. It is up to the reporter to decide which statistics exactly are exposed.

  See the ["Metrics"](#module-metrics) section in the top-level documentation of this module for more
  information.

  ## Example

      summary(
        "db.query.duration",
        tags: [:table],
        unit: {:native, :millisecond}
      )
  """
  @spec summary(metric_name(), metric_options()) :: Summary.t()
  def summary(metric_name, options \\ []) do
    struct(Summary, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of distribution metric.

  Distribution metric builds a histogram of selected measurement's values. It is up to the reporter
  to decide how the boundaries of the distribution buckets are configured - via `:reporter_options`,
  configuration of the aggregating system, or other means.

  See the ["Metrics"](#module-metrics) section in the top-level documentation of this module for more
  information.

  ## Example

      distribution(
        "http.request.duration",
        tags: [:controller, :action],
      )

  """
  @spec distribution(metric_name(), metric_options()) :: Distribution.t()
  def distribution(metric_name, options \\ []) do
    fields = common_fields(metric_name, options)
    struct(Distribution, fields)
  end

  # Helpers

  @spec common_fields(metric_name(), [metric_option() | {atom(), term()}]) :: map()
  defp common_fields(metric_name, options) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    {keep, options} = Keyword.pop(options, :keep)
    {drop, options} = Keyword.pop(options, :drop)
    validate_recording_rule_fun_options!(keep, drop)
    keep = validate_recording_rule_fun!(keep)
    drop = validate_recording_rule_fun!(drop)
    event_name = validate_metric_or_event_name!(event_name)
    {unit, options} = Keyword.pop(options, :unit, :unit)
    {unit, conversion_ratio} = validate_unit!(unit)
    measurement = maybe_convert_measurement(measurement, conversion_ratio)
    validate_metric_options!(options)

    options
    |> fill_in_default_metric_options()
    |> Map.new()
    |> Map.merge(%{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      keep: keep_fun(keep, drop),
      unit: unit
    })
  end

  @spec validate_metric_or_event_name!(term()) :: [atom(), ...]
  defp validate_metric_or_event_name!(metric_or_event_name)
       when metric_or_event_name == [] or metric_or_event_name == "" do
    raise ArgumentError, "metric or event name can't be empty"
  end

  defp validate_metric_or_event_name!(metric_or_event_name) when is_list(metric_or_event_name) do
    if Enum.all?(metric_or_event_name, &is_atom/1) do
      metric_or_event_name
    else
      raise ArgumentError,
            "expected metric or event name to be a list of atoms or a string, " <>
              "got #{inspect(metric_or_event_name)}"
    end
  end

  defp validate_metric_or_event_name!(metric_or_event_name)
       when is_binary(metric_or_event_name) do
    segments = String.split(metric_or_event_name, ".")

    if Enum.any?(segments, &(&1 == "")) do
      raise ArgumentError,
            "metric or event name #{metric_or_event_name} contains leading, " <>
              "trailing or consecutive dots"
    end

    Enum.map(segments, &String.to_atom/1)
  end

  defp validate_metric_or_event_name!(term) do
    raise ArgumentError,
          "expected metric name to be a string or a list of atoms, got #{inspect(term)}"
  end

  defp validate_recording_rule_fun!(nil), do: nil
  defp validate_recording_rule_fun!(fun) when is_function(fun, 1) or is_function(fun, 2), do: fun

  defp validate_recording_rule_fun!(term) do
    raise ArgumentError,
          "expected recording rule to be a function accepting either metadata or metadata and measurements, got #{inspect(term)}"
  end

  defp validate_recording_rule_fun_options!(keep, drop) when is_nil(keep) or is_nil(drop), do: :ok

  defp validate_recording_rule_fun_options!(_keep, _drop) do
    raise ArgumentError,
          "either the keep or drop option may be set, but not both"
  end

  defp keep_fun(nil, nil), do: nil
  defp keep_fun(keep, nil), do: keep
  defp keep_fun(nil, drop) when is_function(drop, 1), do: &(not drop.(&1))
  defp keep_fun(nil, drop) when is_function(drop, 2), do: &(not drop.(&1, &2))

  @spec fill_in_default_metric_options([metric_option()]) :: [metric_option()]
  defp fill_in_default_metric_options(options) do
    Keyword.merge(default_metric_options(), options)
  end

  @spec default_metric_options() :: [metric_option()]
  defp default_metric_options() do
    [
      tags: [],
      tag_values: & &1,
      nil: nil,
      description: nil,
      reporter_options: []
    ]
  end

  @spec validate_metric_options!([metric_option()]) :: :ok | no_return()
  defp validate_metric_options!(options) do
    if tags = Keyword.get(options, :tags), do: validate_tags!(tags)
    if tag_values = Keyword.get(options, :tag_values), do: validate_tag_values!(tag_values)
    if description = Keyword.get(options, :description), do: validate_description!(description)

    if reporter_options = Keyword.get(options, :reporter_options),
      do: validate_reporter_options!(reporter_options)
  end

  @spec validate_tags!(term()) :: :ok | no_return()
  defp validate_tags!(list) when is_list(list) do
    :ok
  end

  defp validate_tags!(term) do
    raise ArgumentError, "expected tag keys to be a list, got: #{inspect(term)}"
  end

  @spec validate_tag_values!(term()) :: :ok | no_return()
  defp validate_tag_values!(fun) when is_function(fun, 1) do
    :ok
  end

  defp validate_tag_values!(term) do
    raise ArgumentError,
          "expected tag_values fun to be a one-argument function, got: #{inspect(term)}"
  end

  @spec validate_description!(term()) :: :ok | no_return()
  defp validate_description!(term) do
    if is_binary(term) and String.valid?(term) do
      :ok
    else
      raise ArgumentError, "expected description to be a string, got #{inspect(term)}"
    end
  end

  @spec validate_reporter_options!(term()) :: :ok | no_return()
  defp validate_reporter_options!(reporter_options) do
    if Keyword.keyword?(reporter_options) do
      :ok
    else
      raise ArgumentError,
            "expected reporter options to be a keyword list, got #{inspect(reporter_options)}"
    end
  end

  @spec maybe_convert_measurement(measurement(), conversion_ratio :: non_neg_integer()) ::
          measurement()
  defp maybe_convert_measurement(measurement, 1) do
    # Don't wrap measurement if no conversion is required.
    measurement
  end

  defp maybe_convert_measurement(measurement, conversion_ratio)
       when is_function(measurement, 2) do
    fn measurements, metadata ->
      if measurement = measurement.(measurements, metadata) do
        measurement * conversion_ratio
      end
    end
  end

  defp maybe_convert_measurement(measurement, conversion_ratio)
       when is_function(measurement, 1) do
    fn measurements ->
      if measurement = measurement.(measurements) do
        measurement * conversion_ratio
      end
    end
  end

  defp maybe_convert_measurement(measurement, conversion_ratio) do
    fn measurements ->
      case measurements do
        %{^measurement => nil} -> nil
        %{^measurement => value} -> value * conversion_ratio
        %{} -> nil
      end
    end
  end

  @spec validate_unit!(term()) :: {unit(), conversion_ratio :: number()} | no_return()
  defp validate_unit!({from_unit, to_unit} = t) do
    cond do
      time_unit?(from_unit) and time_unit?(to_unit) ->
        {to_unit, time_unit_conversion_ratio(from_unit, to_unit)}

      byte_unit?(from_unit) and byte_unit?(to_unit) ->
        {to_unit, byte_unit_conversion_ratio(from_unit, to_unit)}

      true ->
        raise ArgumentError,
              "expected both elements of the unit conversion tuple " <>
                "to represent time or byte units, got #{inspect(t)}"
    end
  end

  defp validate_unit!(unit) when is_atom(unit) do
    {unit, 1}
  end

  defp validate_unit!(term) do
    raise ArgumentError,
          "expected unit to be an atom or a two-element tuple, got #{inspect(term)}"
  end

  # Maybe warn or raise if the result of conversion is 0?
  @spec time_unit_conversion_ratio(time_unit(), time_unit()) :: number()
  defp time_unit_conversion_ratio(unit, unit), do: 1

  defp time_unit_conversion_ratio(from_unit, to_unit) do
    case System.convert_time_unit(1, from_unit, to_unit) do
      0 ->
        1 / System.convert_time_unit(1, to_unit, from_unit)

      ratio ->
        ratio
    end
  end

  @spec byte_unit_conversion_ratio(byte_unit(), byte_unit()) :: number()
  defp byte_unit_conversion_ratio(unit, unit), do: 1

  defp byte_unit_conversion_ratio(from_unit, to_unit) do
    multiplier = byte_unit_factor(to_unit)
    divisor = byte_unit_factor(from_unit)
    1 * multiplier / divisor
  end

  @spec byte_unit_factor(byte_unit()) :: number()
  defp byte_unit_factor(:megabyte), do: 1
  defp byte_unit_factor(:kilobyte), do: 1_000
  defp byte_unit_factor(:byte), do: 1_000_000

  @spec time_unit?(term()) :: boolean()
  defp time_unit?(:native), do: true
  defp time_unit?(:second), do: true
  defp time_unit?(:millisecond), do: true
  defp time_unit?(:microsecond), do: true
  defp time_unit?(:nanosecond), do: true
  defp time_unit?(_), do: false

  @spec byte_unit?(term()) :: boolean()
  defp byte_unit?(:byte), do: true
  defp byte_unit?(:kilobyte), do: true
  defp byte_unit?(:megabyte), do: true
  defp byte_unit?(_), do: false
end
