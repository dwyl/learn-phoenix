# telemetry_poller

[![Test](https://github.com/beam-telemetry/telemetry_poller/actions/workflows/test.yml/badge.svg)](https://github.com/beam-telemetry/telemetry_poller/actions/workflows/test.yml)
[![Codecov](https://codecov.io/gh/beam-telemetry/telemetry_poller/branch/master/graphs/badge.svg)](https://codecov.io/gh/beam-telemetry/telemetry_poller/branch/master/graphs/badge.svg)

Allows to periodically collect measurements and dispatch them as Telemetry events.

`telemetry_poller` by default runs a poller to perform VM measurements:

  * `[vm, memory]` - contains the total memory, process memory, and all other keys in `erlang:memory/0`
  * `[vm, total_run_queue_lengths]` - returns the run queue lengths for CPU and IO schedulers. It contains the `total`, `cpu` and `io` measurements
  * `[vm, system_counts]` - returns the current process, atom and port count as well as their respective limits as per `erlang:system_info/1`
  * `[vm, persistent_term]` - number of terms and memory byte size for `persistent_term`

You can directly consume those events after adding `telemetry_poller` as a dependency.

Poller also provides a convenient API for running custom pollers.

## Defining custom measurements

Poller also includes conveniences for performing process-based measurements as well as custom ones.

### Erlang

First define the poller with the custom measurements. The first measurement is the built-in `process_info` measurement and the second one is given by a custom module-function-args defined  by you:

```erlang
telemetry_poller:start_link(
  [{measurements, [
    {process_info, [{name, my_app_worker}, {event, [my_app, worker]}, {keys, [memory, message_queue_len]}]},
    {example_app_measurements, dispatch_session_count, []}
  ]},
  {period, timer:seconds(10)}, % configure sampling period - default is timer:seconds(5)
  {init_delay, timer:seconds(600)}, % configure sampling initial delay - default is 0
  {name, my_app_poller}
]).
```

Now define the custom measurement and you are good to go:

```erlang
-module(example_app_measurements).

dispatch_session_count() ->
    % emit a telemetry event when called
    telemetry:execute([example_app, session_count], #{count => example_app:session_count()}, #{}).
```

### Elixir

You typically start the poller as a child in your supervision tree:

```elixir
children = [
  {:telemetry_poller,
   # include custom measurement as an MFA tuple
   measurements: [
     {:process_info, name: :my_app_worker, event: [:my_app, :worker], keys: [:memory, :message_queue_len]},
     {ExampleApp.Measurements, :dispatch_session_count, []},
   ],
   period: :timer.seconds(10), # configure sampling period - default is :timer.seconds(5)
   init_delay: :timer.seconds(600), # configure sampling initial delay - default is 0
   name: :my_app_poller}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

The poller above has two periodic measurements. The first is the built-in `process_info` measurement that will gather the memory and message queue length of a process. The second is given by a custom module-function-args defined by you, such as below:

```elixir
defmodule ExampleApp.Measurements do
  def dispatch_session_count() do
    # emit a telemetry event when called
    :telemetry.execute([:example_app, :session_count], %{count: ExampleApp.session_count()}, %{})
  end
end
```

## Documentation

See [documentation](https://hexdocs.pm/telemetry_poller/) for more concrete examples and usage
instructions.

## VM metrics example

### Erlang

Find, in `examples/telemetry_poller_vm.erl`, an example on how to retrieve to VM measurements,
mentioned above.

To see it in action, fire up `rebar3 shell`, then

```erlang
{ok, telemetry_poller_vm} = c("examples/telemetry_poller_vm").
ok = file:delete("telemetry_poller_vm.beam").  % Deletes generated BEAM
ok = telemetry_poller_vm:attach().
```

### Elixir

Find, in `examples/TelemetryPollerVM.ex`, an example on how to retrieve to VM measurements,
mentioned above.

To see it in action, first compile the Erlang sources with `rebar3 compile`.

Then fire up `iex -pa "_build/default/lib/*/ebin"`, then

```elixir
{:ok, _} = Application.ensure_all_started(:telemetry_poller)

[TelemetryPollerVM] = c("examples/TelemetryPollerVM.ex")
:ok = TelemetryPollerVM.attach()
```

## Copyright and License

Copyright (c) 2025 Erlang Ecosystem Foundation.

telemetry_poller source code is released under Apache License, Version 2.0.

See [LICENSE](LICENSE) and [NOTICE](NOTICE) files for more information.
