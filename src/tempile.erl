%%%-------------------------------------------------------------------
%%% File    : tempile.erl
%%% Author  : Russell Brown <russell@pango.lan>
%%% Description : 
%%%
%%% Created : 26 Feb 2010 by Russell Brown <russell@pango.lan>
%%%-------------------------------------------------------------------
-module(tempile).

-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

%% API
-export([start_link/0, render/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-define(SERVER, ?MODULE). 
-record(state, {templates, root, timer, last}).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, application:get_all_env(), []).

%%--------------------------------------------------------------------
%% Function: render() -> iolist()
%% View atom() the template
%% Context dict of name values to render
%% Description: render View with Context
%%--------------------------------------------------------------------
render(View, Context) ->
    gen_server:call(?SERVER, {render, View, Context}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init(Args) ->
    io:format("Starting tempile with env ~p~n", [Args]),
    Root = proplists:get_value(root, Args),
    %% everything in root needs compiling, its name is its key
    {ok, Files} = file:list_dir(Root),
    Dict = compile_templates(Root, Files, dict:new()),
    {ok, TRef} = timer:send_interval(timer:seconds(1), check_templates),
    {ok, #state{templates=Dict, root=Root, timer=TRef, last=stamp()}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({render, View, Context}, _From, State) ->
    Dict = State#state.templates,
    CompiledTemplate = dict:fetch(View, Dict),
    Rendered = mustache:render(undefined, CompiledTemplate, Context),
    {reply, Rendered, State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info(check_templates, State) ->
    Now = stamp(),
    {ok, Files} = file:list_dir(State#state.root),
    Templates = check_files(Files, State#state.root, Now, State#state.last, State#state.templates),
    {noreply, State#state{last=Now, templates=Templates}};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    {ok, cancel} = timer:cancel(State#state.timer),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
compile_templates(_, [], Dict) ->
    Dict;
compile_templates(Root, [H|T], Dict) ->
    case compile_template(filename:join(Root, H)) of 
	{ok, K, V} ->  compile_templates(Root, T, dict:store(K, V, Dict));
	{error, _, _} -> compile_templates(Root, T, Dict)
    end.

compile_template(File) ->
    error_logger:info_msg("Compiling ~p~n", [File]),
    {ok, Bin} = file:read_file(File),
    try mustache:compile(binary_to_list(Bin)) of
	CFun ->  {ok, filename:basename(filename:rootname(File)), CFun}
    catch
	ExType:Mess ->
	    error_logger:error_msg("Failed compiling ~p with ~p:~p~n", [File, ExType, Mess]),
	    {error, ExType, Mess}
    end.

check_files([], _, _, _, Templates) ->
    Templates;
check_files([H|T], Root, Now, Then, Templates) ->
    File = filename:join(Root, H),
    case file:read_file_info(File) of
	{ok, #file_info{mtime=Mtime}} when Mtime >= Then, Mtime < Now ->
	    case compile_template(filename:join(Root, H)) of
		{ok, K, V} ->
		    check_files(T, Root, Now, Then, dict:store(K, V, Templates));
		{error, _, _} ->
		    check_files(T, Root, Now, Then , Templates)
	    end;
	{_, _} ->
	    check_files(T, Root, Now, Then , Templates)
    end.

stamp() ->
    erlang:localtime().
