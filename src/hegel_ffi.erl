%% HERE BE DRAGONS

%% This FFI module was AI provided and accepted without scrutiny.
%% If something seems wrong, it probably is - little thought was given
%% to the correctness or simplicity of this code.

-module(hegel_ffi).
-export([open_port/2, port_send/2, receive_port_data/1, port_connect/2, find_executable/1, ets_new/1, ets_insert/3, ets_lookup/2]).

%% --- PORTS ---

%% Quote a string for safe use in a POSIX shell command.
%% Wraps in single quotes and escapes any embedded single quotes.
shell_quote(Str) ->
    Quoted = string:replace(Str, "'", "'\\''", all),
    "'" ++ Quoted ++ "'".

open_port(Command, Args) ->
    CommandChars = binary_to_list(Command),
    ArgChars = [binary_to_list(A) || A <- Args],

    %% We launch the server via /bin/sh so we can redirect its stderr
    %% to /dev/null.  Without this, benign shutdown messages from
    %% hegel-core's reader thread ("Reader loop exiting:
    %% ConnectionClosedError: Connection closed") leak to the user's
    %% terminal.
    %%
    %% Erlang ports do not support differentiating between stdout/stderr
    %% messages, so wrapper script is the way to go.
    EscapedArgs = [shell_quote(Arg) || Arg <- [CommandChars | ArgChars]],
    ShellCmd = string:join(EscapedArgs, " ") ++ " 2>/dev/null",

    erlang:open_port(
        {spawn_executable, "/bin/sh"},
        [{args, ["-c", ShellCmd]}, binary, use_stdio, exit_status]
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

