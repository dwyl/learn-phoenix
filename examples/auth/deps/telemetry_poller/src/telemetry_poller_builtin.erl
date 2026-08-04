%% @private
-module(telemetry_poller_builtin).

-export([
  memory/0,
  total_run_queue_lengths/0,
  system_counts/0,
  persistent_term/0,
  process_info/3
]).

-spec process_info([atom()], atom(), [atom()]) -> ok.
process_info(Event, Name, Measurements) ->
    case erlang:whereis(Name) of
        undefined -> ok;
        Pid ->
            case erlang:process_info(Pid, Measurements) of
                undefined -> ok;
                Info -> telemetry:execute(Event, maps:from_list(Info), #{name => Name})
            end
    end.

-spec memory() -> ok.
memory() ->
    Measurements = erlang:memory(),
    telemetry:execute([vm, memory], maps:from_list(Measurements), #{}).

-spec total_run_queue_lengths() -> ok.
total_run_queue_lengths() ->
    Total = cpu_stats(total),
    CPU = cpu_stats(cpu),
    telemetry:execute([vm, total_run_queue_lengths], #{
        total => Total,
        cpu => CPU,
        io => Total - CPU},
        #{}).

-spec cpu_stats(total | cpu) -> non_neg_integer().
cpu_stats(total) ->
    erlang:statistics(total_run_queue_lengths_all);
cpu_stats(cpu) ->
    erlang:statistics(total_run_queue_lengths).

-spec system_counts() -> ok.
system_counts() ->
    ProcessCount = erlang:system_info(process_count),
    AtomCount = erlang:system_info(atom_count),
    PortCount = erlang:system_info(port_count),
    ProcessLimit = erlang:system_info(process_limit),
    AtomLimit = erlang:system_info(atom_limit),
    PortLimit = erlang:system_info(port_limit),
    telemetry:execute([vm, system_counts], #{
        process_count => ProcessCount,
        atom_count => AtomCount,
        port_count => PortCount,
        process_limit => ProcessLimit,
        atom_limit => AtomLimit,
        port_limit => PortLimit
    }).

-spec persistent_term() -> ok.
persistent_term() ->
    Info = persistent_term:info(),
    telemetry:execute([vm, persistent_term], Info, #{}).
