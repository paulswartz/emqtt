%%-----------------------------------------------------------------------------
%% Copyright (c) 2012-2015, Feng Lee <feng@emqtt.io>
%% 
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%% 
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.
%%------------------------------------------------------------------------------

-module(emqttc_protocol).

-include("emqttc.hrl").

-include("emqttc_packet.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([initial_state/0,
         parse_opts/2,
         set_socket/2,
         client_id/1]).

-export([handle_packet/3, 
         send_connect/1,
         send_disconnect/1,
         send_publish/2,
         send_subscribe/2,
         send_unsubscribe/2,
         send_ping/2,
         send_packet/2, 
         redeliver/2, 
         shutdown/2]).

-record(will_msg, { retain = false, qos = ?QOS_0, topic, msg}).

%% ------------------------------------------------------------------
%% Protocol State
%% ------------------------------------------------------------------
-record(proto_state, {
    socket,
    socket_name,
    proto_ver,
    proto_name,
    client_id,
    clean_sess,
    keep_alive,
    username,
    password,
    will_topic,
    will_msg,
    will_qos, 
    will_retain,
    packet_id = 1,
    subscriptions  :: map(),
    awaiting_ack   :: map(),
    awaiting_rel   :: map(),
    awaiting_comp  :: map(),
    session = undefined,
    logger
}).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-type(proto_state() :: #proto_state{}).

-spec(send_message({pid() | tuple(), mqtt_message()}, proto_state()) -> {ok, proto_state()}).

-spec(handle_packet(mqtt_packet(), atom(), proto_state()) -> {ok, proto_state()} | {error, any()}). 

-endif.

%%----------------------------------------------------------------------------

-define(PACKET_TYPE(Packet, Type), 
    Packet = #mqtt_packet { header = #mqtt_packet_header { type = Type }}).

-define(PUBACK_PACKET(PacketId), #mqtt_packet_puback { packet_id = PacketId }).

initial_state() ->
	#proto_state {
        proto_ver   = ?MQTT_PROTO_V311,
        proto_name  = <<"MQTT">>,
        clean_sess  = false,
        keep_alive  = 60,
        will_qos    = ?QOS_0,
        will_retain = false
	}. 

parse_opts(ProtoState, []) ->
    ProtoState;
parse_opts(ProtoState, [{client_id, ClientId} | Opts]) when is_binary(ClientId) ->
    parse_opts(ProtoState # proto_state {client_id = ClientId}, Opts);
parse_opts(ProtoState, [{clean_sess, CleanSess} | Opts]) when is_boolean(CleanSess) ->
    parse_opts(ProtoState # proto_state {clean_sess = CleanSess}, Opts);
parse_opts(ProtoState, [{keep_alive, KeepAlive} | Opts]) when is_integer(KeepAlive) ->
    parse_opts(ProtoState # proto_state {keep_alive = KeepAlive}, Opts);
parse_opts(ProtoState, [{username, Username} | Opts]) when is_binary(Username)->
    parse_opts(ProtoState # proto_state { username = Username}, Opts);
parse_opts(ProtoState, [{password, Password} | Opts]) when is_binary(Password) ->
    parse_opts(ProtoState # proto_state { password = Password }, Opts);
parse_opts(ProtoState, [{will_topic, Topic} | Opts]) when is_binary(Topic) ->
    parse_opts(ProtoState # proto_state { will_topic = Topic }, Opts);
parse_opts(ProtoState, [{will_msg, Msg} | Opts]) when is_binary(Msg) ->
    parse_opts(ProtoState # proto_state { will_msg = Msg }, Opts);
parse_opts(ProtoState, [{will_qos, Qos} | Opts]) when ?IS_QOS(Qos) ->
    parse_opts(ProtoState # proto_state { will_qos = Qos }, Opts);
parse_opts(ProtoState, [{will_retain, Retain} | Opts]) when is_boolean(Retain) ->
    parse_opts(ProtoState # proto_state { will_retain = Retain }, Opts);
parse_opts(ProtoState, [{logger, Logger} | Opts]) ->
    parse_opts(ProtoState # proto_state { logger = Logger }, Opts);
parse_opts(ProtoState, [_Opt | Opts]) ->
    parse_opts(ProtoState, Opts).

set_socket(ProtoState, Socket) ->
    {ok, SockName} = emqttc_socket:sockname_s(Socket),
    ProtoState # proto_state {
        socket = Socket,
        socket_name = SockName
    }.

client_id(#proto_state { client_id = ClientId }) -> ClientId.

send_connect(ProtoState) ->
    'TODO',
    {ok, ProtoState}.

send_disconnect(ProtoState) ->
    'TODO',
    {ok, ProtoState}.

send_publish(ProtoState, Msg) ->
    'TODO',
    {ok, ProtoState}.

send_subscribe(ProtoState, Sub) ->
    'TODO',
    {ok, ProtoState}.

send_unsubscribe(ProtoState, Sub) ->
    'TODO',
    {ok, ProtoState}.

send_ping(ProtoState, ping) ->
    'TODO',
    {ok, ProtoState}.

%%CONNECT – Client requests a connection to a Server
handle_packet(?CONNACK, Packet = #mqtt_packet {}, State = #proto_state{session = Session}) ->
    %%create or resume session
	{ok, State};

handle_packet(?PUBLISH, Packet = #mqtt_packet {
                                     header = #mqtt_packet_header {qos = ?QOS_0}},
                                 State = #proto_state{session = Session}) ->
    emqttc_session:publish(Session, {?QOS_0, emqttc_message:from_packet(Packet)}),
	{ok, State};

handle_packet(?PUBLISH, Packet = #mqtt_packet { 
                                     header = #mqtt_packet_header { qos = ?QOS_1 }, 
                                     variable = #mqtt_packet_publish{packet_id = PacketId }}, 
                                 State = #proto_state { session = Session }) ->
    emqttc_session:publish(Session, {?QOS_1, emqttc_message:from_packet(Packet)}),
    send_packet( make_packet(?PUBACK,  PacketId),  State);

handle_packet(?PUBLISH, Packet = #mqtt_packet { 
                                     header = #mqtt_packet_header { qos = ?QOS_2 }, 
                                     variable = #mqtt_packet_publish { packet_id = PacketId } }, 
                                 State = #proto_state { session = Session }) ->
    NewSession = emqttc_session:publish(Session, {?QOS_2, emqttc_message:from_packet(Packet)}),
	send_packet( make_packet(?PUBREC, PacketId), State#proto_state {session = NewSession} );

handle_packet(Puback, #mqtt_packet{variable = ?PUBACK_PACKET(PacketId) }, 
    State = #proto_state { session = Session }) 
    when Puback >= ?PUBACK andalso Puback =< ?PUBCOMP ->

    NewSession = emqttc_session:puback(Session, {Puback, PacketId}),
    NewState = State#proto_state {session = NewSession},
    if 
        Puback =:= ?PUBREC ->
            send_packet( make_packet(?PUBREL, PacketId), NewState);
        Puback =:= ?PUBREL ->
            send_packet( make_packet(?PUBCOMP, PacketId), NewState);
        true ->
            ok
    end,
	{ok, NewState};

handle_packet(?SUBSCRIBE, #mqtt_packet { 
                              variable = #mqtt_packet_subscribe{
                                            packet_id  = PacketId, 
                                            topic_table = TopicTable}, 
                              payload = undefined}, 
                      State = #proto_state { session = Session } ) ->

    Topics = [{Name, Qos} || #mqtt_topic{name=Name, qos=Qos} <- TopicTable], 
    {ok, NewSession, GrantedQos} = emqttc_session:subscribe(Session, Topics),
    send_packet(#mqtt_packet { header = #mqtt_packet_header { type = ?SUBACK }, 
                               variable = #mqtt_packet_suback{ packet_id = PacketId, 
                                                               qos_table  = GrantedQos }}, 
                   State#proto_state{ session = NewSession });

handle_packet(?UNSUBSCRIBE, #mqtt_packet { 
                                variable = #mqtt_packet_subscribe{
                                              packet_id  = PacketId, 
                                              topic_table = Topics }, 
                                payload = undefined}, 
               State = #proto_state{session = Session}) ->
    {ok, NewSession} = emqttc_session:unsubscribe(Session, [Name || #mqtt_topic{ name = Name } <- Topics]), 
    send_packet(#mqtt_packet { header = #mqtt_packet_header {type = ?UNSUBACK }, 
                               variable = #mqtt_packet_suback{packet_id = PacketId }}, 
                           State#proto_state { session = NewSession } );

handle_packet(?PINGREQ, #mqtt_packet{}, State) ->
    send_packet(make_packet(?PINGRESP), State);

handle_packet(?DISCONNECT, #mqtt_packet{}, State) ->
    %%TODO: how to handle session?
    % clean willmsg
    {stop, normal, State#proto_state{will_msg = undefined}}.

make_packet(Type) when Type >= ?CONNECT andalso Type =< ?DISCONNECT -> 
    #mqtt_packet{ header = #mqtt_packet_header { type = Type } }.

make_packet(PubAck, PacketId) when PubAck >= ?PUBACK andalso PubAck =< ?PUBCOMP ->
  #mqtt_packet { header = #mqtt_packet_header { type = PubAck, qos = puback_qos(PubAck) }, 
                 variable = #mqtt_packet_puback { packet_id = PacketId}}.

puback_qos(?PUBACK) ->  ?QOS_0;
puback_qos(?PUBREC) ->  ?QOS_0;
puback_qos(?PUBREL) ->  ?QOS_1;
puback_qos(?PUBCOMP) -> ?QOS_0.

%% qos0 message
send_message({_From, Message = #mqtt_message{ qos = ?QOS_0 }}, State) ->
	send_packet(emqttc_message:to_packet(Message), State);

%% message from session
send_message({_From = SessPid, Message}, State = #proto_state{session = SessPid}) when is_pid(SessPid) ->
	send_packet(emqttc_message:to_packet(Message), State);

%% message(qos1, qos2) not from session
send_message({_From, Message = #mqtt_message{ qos = Qos }}, State = #proto_state{ session = Session }) 
    when (Qos =:= ?QOS_1) orelse (Qos =:= ?QOS_2) ->
    {Message1, NewSession} = emqttc_session:store(Session, Message),
	send_packet(emqttc_message:to_packet(Message1), State#proto_state{session = NewSession}).

send_packet(Packet, State = #proto_state{socket = Sock, socket_name = SocketName, client_id = ClientId, logger = Logger}) ->
    Logger:info("[~s@~s] SENT : ~s", [ClientId, SocketName, emqttc_packet:dump(Packet)]),
    Data = emqttc_packet:serialise(Packet),
    Logger:debug("[~s@~s] SENT: ~p", [ClientId, SocketName, Data]),
    %%FIXME Later...
    erlang:port_command(Sock, Data),
    {ok, State}.

%%
%% @doc redeliver PUBREL PacketId
%%
redeliver({?PUBREL, PacketId}, State) ->
    send_packet( make_packet(?PUBREL, PacketId), State).

shutdown(Error, #proto_state{socket_name = SocketName, client_id = ClientId, will_msg = WillMsg, logger = Logger}) ->
	Logger:info("Protocol ~s@~s Shutdown: ~p", [ClientId, SocketName, Error]),
    ok.

willmsg(Packet) when is_record(Packet, mqtt_packet_connect) ->
    emqttc_message:from_packet(Packet).

clientid(<<>>, #proto_state{socket_name = SocketName}) ->
    <<"emqttc/", (base64:encode(SocketName))/binary>>;

clientid(ClientId, _State) -> ClientId.

%%----------------------------------------------------------------------------

start_keepalive(0) -> ignore;
start_keepalive(Sec) when Sec > 0 ->
    self() ! {keepalive, start, round(Sec * 1.5)}.

%%----------------------------------------------------------------------------
%% Validate Packets
%%----------------------------------------------------------------------------
validate_connect( Connect = #mqtt_packet_connect{} ) ->
    case validate_protocol(Connect) of
        true -> 
            case validate_clientid(Connect) of
                true -> 
                    ?CONNACK_ACCEPT;
                false -> 
                    ?CONNACK_INVALID_ID
            end;
        false -> 
            ?CONNACK_PROTO_VER
    end.

validate_protocol(#mqtt_packet_connect { proto_ver = Ver, proto_name = Name }) ->
    lists:member({Ver, Name}, ?PROTOCOL_NAMES).

validate_clientid(#mqtt_packet_connect { client_id = ClientId }) 
    when ( size(ClientId) >= 1 ) andalso ( size(ClientId) =< ?MAX_CLIENTID_LEN ) ->
    true;

%% MQTT3.1.1 allow null clientId.
validate_clientid(#mqtt_packet_connect { proto_ver =?MQTT_PROTO_V311, client_id = ClientId }) 
    when size(ClientId) =:= 0 ->
    true;

validate_clientid(#mqtt_packet_connect { proto_ver = Ver, clean_sess = CleanSess, client_id = ClientId}) -> 
    %%Logger:warning("Invalid ClientId: ~s, ProtoVer: ~p, CleanSess: ~s", [ClientId, Ver, CleanSess]),
    false.

validate_packet(#mqtt_packet { header  = #mqtt_packet_header { type = ?PUBLISH }, 
                               variable = #mqtt_packet_publish{ topic_name = Topic }}) ->
	case emqttc_topic:validate({name, Topic}) of
	true -> ok;
	false -> {error, badtopic}
	end;

validate_packet(#mqtt_packet { header  = #mqtt_packet_header { type = ?SUBSCRIBE }, 
                               variable = #mqtt_packet_subscribe{topic_table = Topics }}) ->

    validate_topics(filter, Topics);

validate_packet(#mqtt_packet{ header  = #mqtt_packet_header { type = ?UNSUBSCRIBE }, 
                              variable = #mqtt_packet_subscribe{ topic_table = Topics }}) ->

    validate_topics(filter, Topics);

validate_packet(_Packet) -> 
    ok.

validate_topics(Type, []) when Type =:= name orelse Type =:= filter ->
    {error, empty_topics};

validate_topics(Type, Topics) when Type =:= name orelse Type =:= filter ->
	ErrTopics = [Topic || #mqtt_topic{name=Topic, qos=Qos} <- Topics,
						not (emqttc_topic:validate({Type, Topic}) and validate_qos(Qos))],
	case ErrTopics of
	[] -> ok;
	_ -> {error, badtopic}
	end.

validate_qos(undefined) -> true;
validate_qos(Qos) when Qos =< ?QOS_2 -> true;
validate_qos(_) -> false.

