## A thin connection between machines over Godot's MultiplayerPeer: ENet
## (desktop, Android) or WebSocket (the browser; WebRTC is the later browser
## option, same MultiplayerPeer API) behind one API. Packets only, no RPCs, no
## scene replication: what goes in them is net_wire.gd's, what is done with
## them net_sync.gd's (docs/multiplayer.md).
##
##   var host := NetSession.host(NetSession.PORT)            # null: failed
##   var client := NetSession.join("127.0.0.1", NetSession.PORT)
##   client.send(NetSession.HOST_ID, NetSession.CH_INPUTS, bytes)
##   for packet in host.poll(now_ms): # [from, bytes]
##
## poll() must be called often (each tick). For tests it can add latency,
## jitter and loss to what this side sends (lag_ms, jitter_ms, loss, timed by
## the now_ms handed to poll); loss only drops unreliable packets, as the
## network would (ENet resends reliable ones itself).
class_name NetSession
extends RefCounted

enum Transport { ENET, WEBSOCKET }

const PORT := 47197
const HOST_ID := 1
## ENet channels: reliable messages (hello, welcome, big snapshots), the
## inputs (unreliable, sent redundantly), small snapshot deltas (unreliable).
const CHANNELS := 3
const CH_RELIABLE := 0
const CH_INPUTS := 1
const CH_SNAPS := 2
## An unreliable packet bigger than this goes reliable instead: ENet splits a
## big unreliable packet and loses all of it when one piece is lost (and
## warns each time).
const MTU_SAFE := 1200
## A guess at each packet's headers on the wire (IPv4 20, UDP 8, ENet's own
## about 16), for the bandwidth a report gives besides the payload.
const HEADER_BYTES := 44

var peer: MultiplayerPeer = null
var transport := Transport.ENET
var hosting := false
## Test conditions on what this side sends.
var lag_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0
## Payload bytes and packets each way, and unreliable packets the test's loss
## dropped.
var sent := 0
var sent_packets := 0
var received := 0
var received_packets := 0
var dropped := 0
## Peers that joined or left since take_events() was last called.
var joined: Array[int] = []
var left: Array[int] = []
var _queue: Array = []
var _last_due := {}
var _now := 0.0
var _dice := RandomNumberGenerator.new()


## Listens on `port` for up to `max_clients`; null when the port is taken.
static func host(port := PORT, kind := Transport.ENET, max_clients := 3, bind := "*") -> NetSession:
	var s := NetSession.new()
	s.transport = kind
	s.hosting = true
	var err := ERR_UNAVAILABLE
	if kind == Transport.ENET:
		var enet := ENetMultiplayerPeer.new()
		enet.set_bind_ip(bind)
		err = enet.create_server(port, max_clients, CHANNELS)
		s.peer = enet
	else:
		var ws := _websocket()
		err = ws.create_server(port, bind)
		s.peer = ws
	if err != OK:
		return null
	s._wire()
	return s


## Connects to a host at `address`; null when it cannot even start (connected()
## says when it is through).
static func join(address: String, port := PORT, kind := Transport.ENET) -> NetSession:
	var s := NetSession.new()
	s.transport = kind
	var err := ERR_UNAVAILABLE
	if kind == Transport.ENET:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(address, port, CHANNELS)
		s.peer = enet
	else:
		var ws := _websocket()
		err = ws.create_client("ws://%s:%d" % [address, port])
		s.peer = ws
	if err != OK:
		return null
	s._wire()
	return s


func _wire() -> void:
	_dice.seed = 1997
	peer.peer_connected.connect(func(id: int) -> void: joined.append(id))
	peer.peer_disconnected.connect(func(id: int) -> void: left.append(id))


func connected() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## This side's peer id (the host is HOST_ID).
func id() -> int:
	return peer.get_unique_id() if peer != null else 0


## [joined, left] since the last call.
func take_events() -> Array:
	var out := [joined.duplicate(), left.duplicate()]
	joined.clear()
	left.clear()
	return out


## Sends `bytes` to peer `to` (0: everyone) on `channel`: CH_RELIABLE is
## reliable, the others unreliable unless the packet is over MTU_SAFE.
func send(to: int, channel: int, bytes: PackedByteArray) -> void:
	if peer == null:
		return
	# A WebSocket is TCP underneath: everything arrives, in order.
	var reliable := (
		channel == CH_RELIABLE or bytes.size() > MTU_SAFE or transport == Transport.WEBSOCKET
	)
	if reliable and channel != CH_RELIABLE:
		channel = CH_RELIABLE
	sent += bytes.size()
	sent_packets += 1
	if lag_ms <= 0.0 and jitter_ms <= 0.0 and loss <= 0.0:
		_put(to, channel, reliable, bytes)
		return
	if not reliable and _dice.randf() < loss:
		dropped += 1
		return
	var due := _now + lag_ms + _dice.randf() * jitter_ms
	if reliable:
		# Reliable packets keep their order whatever the jitter.
		due = maxf(due, float(_last_due.get(channel, 0.0)))
		_last_due[channel] = due
	_queue.append([due, to, channel, reliable, bytes])


func _put(to: int, channel: int, reliable: bool, bytes: PackedByteArray) -> void:
	peer.set_target_peer(to)
	if transport == Transport.ENET:
		peer.transfer_channel = channel
		peer.transfer_mode = (
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
			if reliable
			else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		)
	peer.put_packet(bytes)


## Sends what the test's latency held back and is now due, services the
## connection and returns what came in: [[from, bytes], ...].
func poll(now_ms: float) -> Array:
	_now = now_ms
	if peer == null:
		return []
	if not _queue.is_empty():
		var keep: Array = []
		for item: Array in _queue:
			if float(item[0]) <= now_ms:
				_put(int(item[1]), int(item[2]), bool(item[3]), item[4])
			else:
				keep.append(item)
		_queue = keep
	peer.poll()
	var out: Array = []
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var bytes := peer.get_packet()
		received += bytes.size()
		received_packets += 1
		out.append([from, bytes])
	return out


func close() -> void:
	if peer != null:
		peer.close()
		peer = null


## A WebSocket peer with room for a whole snapshot in one message.
static func _websocket() -> WebSocketMultiplayerPeer:
	var ws := WebSocketMultiplayerPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	return ws
