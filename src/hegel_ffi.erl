%% HERE BE DRAGONS

%% This FFI module was AI provided and accepted without scrutiny.
%% If something seems wrong, it probably is - no thought was given
%% to the correctness or simplicity of this code.

-module(hegel_ffi).
-export([open_port/2, port_send/2, receive_port_data/1, port_connect/2, find_executable/1, ets_new/1, ets_insert/3, ets_lookup/2]).

%% --- PORTS ---

open_port(Command, Args) ->
    CommandChars = binary_to_list(Command),
    ArgChars = [binary_to_list(A) || A <- Args],

    %% https://www.erlang.org/doc/apps/erts/erlang.html#open_port/2
    erlang:open_port(
        {spawn_executable, CommandChars},
        [{args, ArgChars}, binary, use_stdio, exit_status]
    ).

port_send(Port, Data) ->
    erlang:port_command(Port, Data),
    nil.

port_connect(Port, Pid) ->
    erlang:port_connect(Port, Pid),
    nil.

receive_port_data(Port) ->
    receive
        {Port, {data, Data}} ->
            {ok, Data};
        {Port, {exit_status, _Code}} ->
            {error, nil}
    end.

%% --- EXECUTABLE ---
find_executable(Name) ->
    case os:find_executable(binary_to_list(Name)) of
        false -> {error, nil};
        Path -> {ok, list_to_binary(Path)}
    end.

%% --- ETS ---
ets_new(Name) ->
    ets:new(binary_to_atom(Name), [set, named_table, public, {read_concurrency, true}]).

ets_insert(Table, Key, Value) ->
    ets:insert(Table, {Key, Value}),
    nil.

ets_lookup(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{_, Value}] -> {ok, Value};
        [] -> {error, nil}
    end.

