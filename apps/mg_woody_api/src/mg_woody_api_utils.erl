-module(mg_woody_api_utils).
-include_lib("mg_proto/include/mg_proto_state_processing_thrift.hrl").

%% API
-export([handle_safe_with_retry /5]).
-export([opaque_to_woody_context/1]).
-export([woody_context_to_opaque/1]).

%%
%% API
%%
-type ctx() :: mg:request_context().
-type logger() :: mg_machine_logger:handler().

-spec handle_safe_with_retry(mg_events_machine:ref(), ctx(), fun(() -> R), mg_utils:deadline(), logger()) ->
    R.
handle_safe_with_retry(Ref, ReqCtx, F, Deadline, Logger) ->
    handle_safe_with_retry_(
        Ref, ReqCtx, F,
        genlib_retry:exponential({max_total_timeout, mg_utils:deadline_to_timeout(Deadline)}, 2, 10),
        Logger
    ).

-spec handle_safe_with_retry_(mg_events_machine:ref(), ctx(), fun(() -> R), genlib_retry:strategy(), logger()) ->
    R.
handle_safe_with_retry_(Ref, ReqCtx, F, Retry, Logger) ->
    try
        F()
    catch throw:Error ->
        ok = mg_machine_logger:handle_event(
                Logger, {request_event, Ref, ReqCtx, {request_failed, {throw, Error, erlang:get_stacktrace()}}}
            ),
        case handle_error(Error, genlib_retry:next_step(Retry))  of
            {rethrow, NewError} ->
                erlang:throw(NewError);
            {woody_error, {WoodyErrorClass, Description}} ->
                BinaryDescription = erlang:list_to_binary(io_lib:format("~9999p", [Description])),
                woody_error:raise(system, {internal, WoodyErrorClass, BinaryDescription});
            {retry_in, Timeout, NewRetry} ->
                ok = mg_machine_logger:handle_event(
                        Logger, {request_event, Ref, ReqCtx, {retrying, Timeout}}
                    ),
                ok = timer:sleep(Timeout),
                handle_safe_with_retry_(Ref, ReqCtx, F, NewRetry, Logger)
        end
    end.

-spec handle_error(mg_machine:thrown_error() | namespace_not_found, {wait, _, _} | finish) ->
    {rethrow, _} | {woody_error, {woody_error:class(), _Details}} | {retry_in, pos_integer(), genlib_retry:strategy()}.
handle_error(machine_not_found      , _) -> {rethrow, #'MachineNotFound'      {}};
handle_error(machine_already_exist  , _) -> {rethrow, #'MachineAlreadyExists' {}};
handle_error(machine_failed         , _) -> {rethrow, #'MachineFailed'        {}};
handle_error(machine_already_working, _) -> {rethrow, #'MachineAlreadyWorking'{}};
handle_error(namespace_not_found    , _) -> {rethrow, #'NamespaceNotFound'    {}};
handle_error(event_sink_not_found   , _) -> {rethrow, #'EventSinkNotFound'    {}};

% может Reason не прокидывать дальше?
% TODO logs
handle_error({transient, _     }, {wait, Timeout, NewStrategy}) -> {retry_in, Timeout, NewStrategy};
handle_error({transient, Reason}, finish                      ) -> {woody_error, {resource_unavailable, Reason}};
handle_error(Reason={timeout, _}, _                           ) -> {woody_error, {result_unknown      , Reason}};

handle_error(UnknownError, _) -> erlang:error(badarg, [UnknownError]).

%%
%% packer to opaque
%%
-spec opaque_to_woody_context(mg_storage:opaque()) ->
    woody_context:ctx().
opaque_to_woody_context([1, RPCID, ContextMeta]) ->
    #{
        rpc_id => opaque_to_woody_rpc_id(RPCID),
        meta   => ContextMeta
    };
opaque_to_woody_context([1, RPCID]) ->
    #{
        rpc_id => opaque_to_woody_rpc_id(RPCID)
    }.

-spec woody_context_to_opaque(woody_context:ctx()) ->
    mg_storage:opaque().
woody_context_to_opaque(#{rpc_id := RPCID, meta := ContextMeta}) ->
    [1, woody_rpc_id_to_opaque(RPCID), ContextMeta];
woody_context_to_opaque(#{rpc_id := RPCID}) ->
    [1, woody_rpc_id_to_opaque(RPCID)].

-spec woody_rpc_id_to_opaque(woody:rpc_id()) ->
    mg_storage:opaque().
woody_rpc_id_to_opaque(#{span_id := SpanID, trace_id := TraceID, parent_id := ParentID}) ->
    [SpanID, TraceID, ParentID].

-spec opaque_to_woody_rpc_id(mg_storage:opaque()) ->
    woody:rpc_id().
opaque_to_woody_rpc_id([SpanID, TraceID, ParentID]) ->
    #{span_id => SpanID, trace_id => TraceID, parent_id => ParentID}.
