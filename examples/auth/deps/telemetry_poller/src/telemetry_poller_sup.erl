%% @private
-module(telemetry_poller_sup).

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link(PollerChildSpec) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, PollerChildSpec).

init(PollerChildSpec) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    {ok, {SupFlags, PollerChildSpec}}.
