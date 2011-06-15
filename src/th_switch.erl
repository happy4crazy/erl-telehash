% switch handles sending and receiving telexes
% the gen_server manages the udp socket
% the gen_event allows other processes to subscribe to incoming/outgoing telexes

-module(th_switch).

-include("conf.hrl").
-include("types.hrl").
-include("log.hrl").

-export([start_link/0, listen/0, deafen/0, send/2, recv/2, notify/1]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {socket}).
-define(EVENT, th_switch_event).
-define(SERVER, th_switch_server).
-define(HANDLER, th_switch_handler).

% --- api ---

-spec start_link() -> {ok, pid(), pid()}.
start_link() ->
    {ok, Gen_event} = gen_event:start_link({local, ?EVENT}),
    {ok, Gen_server} = gen_server:start_link({local, ?SERVER}, ?MODULE, [], []),
    {ok, Gen_event, Gen_server}.

-spec listen() -> ok.
listen() ->
    ok = gen_event:add_sup_handler(?EVENT, {?HANDLER, self()}, self()).

-spec deafen() -> ok.
deafen() ->
    ok = gen_event:delete_handler(?EVENT, {?HANDLER, self()}, deafen).

-spec send(address(), telex:telex()) -> ok.
send(#address{}=Address, Telex) ->
    gen_server:cast(?SERVER, {send, Address, Telex}).

% for testing / debugging
-spec recv(address(), binary()) -> ok.
recv(#address{}=Address, Packet) ->
    gen_server:cast(?SERVER, {recv, Address, Packet}).

-spec notify(term()) -> ok.
notify(Event) ->
    gen_event:notify(?EVENT, Event).

% --- gen_server callbacks ---

init([]) ->
    {ok, Socket} = gen_udp:open(?DEFAULT_PORT, [binary]),
    {ok, #state{socket=Socket}}.

handle_call(_Request, _From, State) ->
    {noreply, State}.

handle_cast({send, #address{host=Host, port=Port}=Address, Telex}, #state{socket=Socket}=State) ->
    Telex2 = th_telex:set(Telex, '_to', th_util:address_to_binary(Address)),
    try gen_udp:send(Socket, Host, Port, th_telex:encode(Telex2)) of
	   ok ->
	       ?INFO([send, {address, Address}, {telex, Telex2}]),
	       gen_event:notify(?EVENT, {send, Address, Telex2});
	   Error ->
	       ?WARN([send_error, {address, Address}, {telex, Telex2}, {error, Error}])
    catch
	_:Error ->
	    ?WARN([send_error, {address, Address}, {telex, Telex2}, {error, Error}, {trace, erlang:get_stacktrace()}])
    end,
    {noreply, State};
handle_cast({recv, #address{}=Address, Packet}, State) -> 
    handle_recv(Address, Packet),
    {noreply, State};
handle_cast(_Packet, State) ->
    {noreply, State}.

handle_info({udp, Socket, Host, Port, Packet}, #state{socket=Socket}=State) ->
    Address = #address{host=Host, port=Port},
    handle_recv(Address, Packet),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{socket=Socket}) ->
    gen_udp:close(Socket),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% --- internal functions ---

-spec handle_recv(address(), binary()) -> ok.
handle_recv(Address, Packet) ->
    try th_telex:decode(Packet) of
	   Telex ->
	       ?INFO([recv, {address, Address}, {telex, Telex}]),
	       gen_event:notify(?EVENT, {recv, Address, Telex})
    catch
	error:({telex, _, _, _}=Error) ->
	    ?WARN([recv_error, {address, Address}, {packet, Packet}, {error, Error}])
    end.

% --- end ---
