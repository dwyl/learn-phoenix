-if(?OTP_RELEASE >= 27).
-define(MODULEDOC(Str), -moduledoc(Str)).
-define(DOC(Str), -doc(Str)).
-else.
-define(MODULEDOC(Str), -compile([])).
-define(DOC(Str), -compile([])).
-endif.

-module(telemetry_poller).

?MODULEDOC("""
A time-based poller to periodically dispatch Telemetry events.

A poller is a process start in your supervision tree with a list
of measurements to perform periodically. On start it expects the
period in milliseconds and a list of measurements to perform. Initial delay
is an optional parameter that sets time delay in milliseconds before starting
measurements:

<!-- tabs-open -->

### Erlang

```
telemetry_poller:start_link([
    {measurements, Measurements},
    {period, Period},
    {init_delay, InitDelay}
])
```

### Elixir

```
:telemetry_poller.start_link(
    measurements: measurements,
    period: period,
    init_delay: init_delay
)
```

<!-- tabs-close -->

## Measurements

The following measurements are supported:

  * `memory` (default)
  * `total_run_queue_lengths` (default)
  * `system_counts` (default)
  * `persistent_term` (default)
  * `{process_info, Proplist}`
  * `{Module, Function, Args}`

We will discuss each measurement in detail. Also note that the
`telemetry_poller` application ships with a built-in poller that
measures `memory`, `total_run_queue_lengths`, `system_counts`, and `persistent_term`. This takes
the VM measurement out of the way so your application can focus
on what is specific to its behaviour.

### Memory

An event emitted as `[vm, memory]`. The measurement includes all
the key-value pairs returned by the `erlang:memory/0` function,
e.g. `total` for total memory, `processes_used` for memory used by
all processes, and so on.

### Total run queue lengths

On startup, the Erlang VM starts many schedulers to do both IO and
CPU work. If a process needs to do some work or wait on IO, it is
allocated to the appropriate scheduler. The measurement includes the
following keys:

  * `total` - all schedulers (CPU + IO)
  * `cpu` - CPU schedulers
  * `io` - IO schedulers

### System counts

The measurement includes:

  * `process_count` - the number of processes currently existing at the local node
  * `atom_count` - the number of atoms currently existing at the local node
  * `port_count` - the number of ports currently existing at the local node
  * `process_limit` - the maximum number of processes allowed at the local node
  * `atom_limit` - the maximum number of atoms allowed at the local node
  * `port_limit` - the maximum number of ports allowed at the local node

### Persistent term (since 1.2.0)

An event emitted as `[vm, persistent_term]`. The measurement includes information
about persistent terms in the system, as returned by `persistent_term:info/0`:

  * `count` - The number of persistent terms
  * `memory` - The total amount of memory (measured in bytes) used by all persistent terms

### Process info

A measurement with information about a given process. It must be specified
alongside a proplist with the process name, the event name, and a list of
keys to be included:

<!-- tabs-open -->

### Erlang

```erlang
{process_info, [
 {name, my_app_worker},
 {event, [my_app, worker]},
 {keys, [message_queue_len, memory]}
]}
```

### Elixir

```elixir
{:process_info, [
 name: my_app_worker,
 event: [my_app, worker],
 keys: [message_queue_len, memory]
]}
```

<!-- tabs-close -->

### Custom measurements

Telemetry poller also allows you to perform custom measurements by passing
a module-function-args tuple:

<!-- tabs-open -->

### Erlang

```erlang
{my_app_example, measure, []}
```

### Elixir

```elixir
{MyApp.Example, :measure, []}
```

<!-- tabs-close -->

The given function will be invoked periodically and they must explicitly invoke the
`telemetry:execute/3` function. If the invocation of the MFA fails,
the measurement is removed from the Poller.

For all options, see `start_link/1`. The options listed there can be given
to the default poller as well as to custom pollers.

### Default poller

A default poller is started with `telemetry_poller` responsible for emitting
measurements for `memory` and `total_run_queue_lengths`. You can customize
the behaviour of the default poller by setting the `default` key under the
`telemetry_poller` application environment. Setting it to `false` disables
the poller.

## Examples

### Example 1: tracking number of active sessions in web application

Let's imagine that you have a web application and you would like to periodically
measure number of active user sessions.

<!-- tabs-open -->

### Erlang

```erlang
-module(example_app).

session_count() ->
   % logic for calculating session count.
```

### Elixir

```elixir
defmodule ExampleApp do
  def session_count do
    # logic for calculating session count
  end
end
```

<!-- tabs-close -->

To achieve that, we need a measurement dispatching the value we're interested in:

<!-- tabs-open -->

### Erlang

```erlang
-module(example_app_measurements).

dispatch_session_count() ->
   telemetry:execute([example_app, session_count], example_app:session_count()).
```

### Elixir

```elixir
defmodule ExampleApp.Measurements do
  def dispatch_session_count do
    :telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
  end
end
```

<!-- tabs-close -->

and tell the Poller to invoke it periodically:

<!-- tabs-open -->

### Erlang

```erlang
telemetry_poller:start_link([{measurements, [{example_app_measurements, dispatch_session_count, []}]).
```

### Elixir

```elixir
:telemetry_poller.start_link(measurements: [{ExampleApp.Measurements, :dispatch_session_count, []}])
```

<!-- tabs-close -->

If you find that you need to somehow label the event values, e.g. differentiate between number of
sessions of regular and admin users, you could use event metadata:

<!-- tabs-open -->

### Erlang

```erlang
-module(example_app_measurements).

dispatch_session_count() ->
   Regulars = example_app:regular_users_session_count(),
   Admins = example_app:admin_users_session_count(),
   telemetry:execute([example_app, session_count], #{count => Admins}, #{role => admin}),
   telemetry:execute([example_app, session_count], #{count => Regulars}, #{role => regular}).
```

### Elixir

```elixir
defmodule ExampleApp.Measurements do
  def dispatch_session_count do
    regulars = ExampleApp.regular_users_session_count()
    admins = ExampleApp.admin_users_session_count()
    :telemetry.execute([:example_app, :session_count], %{count: admins}, %{role: :admin})
    :telemetry.execute([:example_app, :session_count], %{count: regulars}, %{role: :regular})
  end
end
```

<!-- tabs-close -->

> #### Note {: .info}
>
> The other solution would be to dispatch two different events by hooking up
> `example_app:regular_users_session_count/0` and `example_app:admin_users_session_count/0`
> functions directly. However, if you add more and more user roles to your app, you'll find
> yourself creating a new event for each one of them, which will force you to modify existing
event handlers. If you can break down event value by some feature, like user role in this
example, it's usually better to use event metadata than add new events.

This is a perfect use case for poller, because you don't need to write a dedicated process
which would call these functions periodically. Additionally, if you find that you need to collect
more statistics like this in the future, you can easily hook them up to the same poller process
and avoid creating lots of processes which would stay idle most of the time.
""").

-behaviour(gen_server).

%% API
-export([
    child_spec/1,
    list_measurements/1,
    start_link/1
]).

-export([code_change/3, handle_call/3, handle_cast/2,
     handle_info/2, init/1, terminate/2]).

-export_type([
              option/0,
              options/0,
              measurement/0,
              period/0]).

-include_lib("kernel/include/logger.hrl").

?DOC("""
The reference to a poller process.
""").
-type t() :: gen_server:server_ref().

?DOC("""
A list of options for the poller.
""").
-type options() :: [option()].

?DOC("""
An option for the poller.
""").
-type option() ::
    {name, atom() | gen_server:server_name()}
    | {period, period()}
    | {init_delay, init_delay()}
    | {measurements, [measurement()]}.

?DOC("""
A measurement for the poller.
""").
-type measurement() ::
    memory
    | total_run_queue_lengths
    | system_counts
    | persistent_term
    | {process_info, [{name, atom()} | {event, [atom()]} | {keys, [atom()]}]}
    | {module(), atom(), list()}.

?DOC("""
A period for the poller.
""").
-type period() :: pos_integer().

?DOC("""
An init delay for the poller.
""").
-type init_delay() :: non_neg_integer().

-type state() :: #{measurements => [measurement()], period => period()}.

?DOC("""
Starts a poller linked to the calling process.

Useful for starting Pollers as a part of a supervision tree.

## Options

The default options are:

  * `{name, telemetry_poller}`
  * `{period, timer:seconds(5)}`
  * `{init_delay, 0}`

""").
-spec start_link(options()) -> gen_server:start_ret().
start_link(Opts) when is_list(Opts) ->
    Args = parse_args(Opts),

    case lists:keyfind(name, 1, Opts) of
        {name, Name} when is_atom(Name) -> gen_server:start_link({local, Name}, ?MODULE, Args, []);
        {name, Name} -> gen_server:start_link(Name, ?MODULE, Args, []);
        false -> gen_server:start_link(?MODULE, Args, [])
    end.

?DOC("""
Returns a list of measurements used by the poller.
""").
-spec list_measurements(t()) -> [measurement()].
list_measurements(Poller) ->
    gen_server:call(Poller, get_measurements).

?DOC(false).
-spec init(map()) -> {ok, state()}.
init(Args) ->
    schedule_measurement(maps:get(init_delay, Args)),
    {ok, #{
        measurements => maps:get(measurements, Args),
        period => maps:get(period, Args)}}.
?DOC("""
    Returns a child spec for the poller for running under a supervisor.
""").
-spec child_spec(options()) -> supervisor:child_spec().
child_spec(Opts) ->
    Id =
        case proplists:get_value(name, Opts) of
            undefined -> ?MODULE;
            Name when is_atom(Name) -> Name;
            {global, Name} -> Name;
            {via, _, Name} -> Name
        end,

    #{
        id => Id,
        start => {telemetry_poller, start_link, [Opts]}
    }.

parse_args(Args) ->
    Measurements = proplists:get_value(measurements, Args, []),
    Period = proplists:get_value(period, Args, timer:seconds(5)),
    InitDelay = proplists:get_value(init_delay, Args, 0),
    #{
        measurements => parse_measurements(Measurements),
        period => validate_period(Period),
        init_delay => validate_init_delay(InitDelay)
    }.

-spec schedule_measurement(non_neg_integer()) -> ok.
schedule_measurement(CollectInMillis) ->
    erlang:send_after(CollectInMillis, self(), collect), ok.

-spec validate_period(term()) -> period() | no_return().
validate_period(Period) when is_integer(Period), Period > 0 ->
    Period;
validate_period(Term) ->
    erlang:error({badarg, "Expected period to be a positive integer"}, [Term]).

-spec validate_init_delay(term()) -> init_delay() | no_return().
validate_init_delay(InitDelay) when is_integer(InitDelay), InitDelay >= 0 ->
    InitDelay;
validate_init_delay(Term) ->
    erlang:error({badarg, "Expected init_delay to be 0 or a positive integer"}, [Term]).

-spec parse_measurements([measurement()]) -> [{module(), atom(), list()}].
parse_measurements(Measurements) when is_list(Measurements) ->
    lists:map(fun parse_measurement/1, Measurements);
parse_measurements(Term) ->
    erlang:error({badarg, "Expected measurements to be a list"}, [Term]).

-spec parse_measurement(measurement()) -> {module(), atom(), list()}.
parse_measurement(memory) ->
    {telemetry_poller_builtin, memory, []};
parse_measurement(total_run_queue_lengths) ->
    {telemetry_poller_builtin, total_run_queue_lengths, []};
parse_measurement(system_counts) ->
    {telemetry_poller_builtin, system_counts, []};
parse_measurement(persistent_term) ->
    {telemetry_poller_builtin, persistent_term, []};
parse_measurement({process_info, List}) when is_list(List) ->
    Name = case proplists:get_value(name, List) of
        undefined -> erlang:error({badarg, "Expected `name' key to be given under process_info measurement"});
        PropName when is_atom(PropName) -> PropName;
        PropName -> erlang:error({badarg, "Expected `name' key to be an atom under process_info measurement"}, [PropName])
    end,

    Event = case proplists:get_value(event, List) of
        undefined -> erlang:error({badarg, "Expected `event' key to be given under process_info measurement"});
        PropEvent when is_list(PropEvent) -> PropEvent;
        PropEvent -> erlang:error({badarg, "Expected `event' key to be a list of atoms under process_info measurement"}, [PropEvent])
    end,

    Keys = case proplists:get_value(keys, List) of
        undefined -> erlang:error({badarg, "Expected `keys' key to be given under process_info measurement"});
        PropKeys when is_list(PropKeys) -> PropKeys;
        PropKeys -> erlang:error({badarg, "Expected `keys' key to be a list of atoms under process_info measurement"}, [PropKeys])
    end,

    {telemetry_poller_builtin, process_info, [Event, Name, Keys]};
parse_measurement({M, F, A}) when is_atom(M), is_atom(F), is_list(A) ->
    {M, F, A};
parse_measurement(Term) ->
    erlang:error({badarg, "Expected measurement to be memory, total_run_queue_lengths, {process_info, list()}, or a {module(), function(), list()} tuple"}, [Term]).

-spec make_measurements_and_filter_misbehaving([measurement()]) -> [measurement()].
make_measurements_and_filter_misbehaving(Measurements) ->
    [Measurement || Measurement <- Measurements, make_measurement(Measurement) =/= error].

-spec make_measurement(measurement()) -> measurement() | no_return().
make_measurement(Measurement = {M, F, A}) ->
    try erlang:apply(M, F, A) of
        _ -> Measurement
    catch
        Class:Reason:Stacktrace ->
            ?LOG_ERROR("Error when calling MFA defined by measurement: ~p ~p ~p~n"
                        "Class=~p~nReason=~p~nStacktrace=~p~n",
                        [M, F, A, Class, Reason, Stacktrace]),
                               error
    end.

?DOC(false).
handle_call(get_measurements, _From, State = #{measurements := Measurements}) ->
    {reply, Measurements, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

?DOC(false).
handle_cast(_Msg, State) -> {noreply, State}.

?DOC(false).
handle_info(collect, State) ->
    GoodMeasurements = make_measurements_and_filter_misbehaving(maps:get(measurements, State)),
    schedule_measurement(maps:get(period, State)),
    {noreply, State#{measurements := GoodMeasurements}};
handle_info(_, State) ->
    {noreply, State}.

?DOC(false).
terminate(_Reason, _State) -> ok.

?DOC(false).
code_change(_OldVsn, State, _Extra) -> {ok, State}.
