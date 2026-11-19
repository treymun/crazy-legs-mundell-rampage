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
## the now_ms handed to poll); loss drops unreliable packets and makes a
## reliable one late by a resend, holding up its channel, as the network
## would (ENet resends reliable ones itself).
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
const PATIENCE_MS := 15000
## ENet's throttle (_patient): looked at every THROTTLE_INTERVAL ms, back up
## by THROTTLE_BACK (its whole scale, 32) at once, never slowed.
const THROTTLE_INTERVAL := 1
const THROTTLE_BACK := 32
## On: ENet's throttle as it comes (net_lag.gd's before).
static var throttle := false
## The test's loss also hits reliable packets (pass 12): one "lost" is
## resent after a round trip and RESEND_MS, holding up its channel. Off: a
## reliable packet is never lost (the old test, blind to that stall).
static var resend_lost := true
const RESEND_MS := 20.0
## A lobby server's WebSocket players (the browser) come through `also`, their
## ids raised past the 31 bits either transport hands out, so they never meet.
const ALSO_IDS := 1 << 32

var peer: MultiplayerPeer = null
## A second session merged into this one (an always-open lobby's WebSocket
## side, for the browser build): its peers are this one's past ALSO_IDS.
var also: NetSession = null
var transport := Transport.ENET
var hosting := false
## The party line (net_relay.gd) sharing this session's port: it is handed
## every packet whose first byte is NetWire.RELAY_FIRST or more and everything
## from a peer it claimed (`claim`), and those peers are left out of this
## session's broadcasts, drops and events. `tap_slot` is its number for them.
var tap: NetRelay = null
var tap_slot := 0
var _claimed := {}
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
## Reliable packets the test's loss made late (resend_lost).
var resent := 0
## Peers that joined or left since take_events() was last called.
var joined: Array[int] = []
var left: Array[int] = []
var _queue: Array = []
var _last_due := {}
## The peers connected now.
var _peers := {}
var _now := 0.0
var _dice := RandomNumberGenerator.new()


## Listens on `port` for up to `max_clients`; null when the port is taken.
static func host(
	port := PORT, kind := Transport.ENET, max_clients := 3, bind := "*", tls: TLSOptions = null
) -> NetSession:
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
		err = ws.create_server(port, bind, tls)
		s.peer = ws
	if err != OK:
		return null
	s._wire()
	return s


## Connects to a host at `address`; null when it cannot even start (connected()
## says when it is through).
static func join(address: String, port := PORT, kind := Transport.ENET) -> NetSession:
	var s := NetSession.new()
	return s if s.dial(address, port, kind) else null


## Starts this session connecting to `address` (join(); a RelayLink's own).
func dial(address: String, port := PORT, kind := Transport.ENET) -> bool:
	transport = kind
	var err := ERR_UNAVAILABLE
	if kind == Transport.ENET:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(address, port, CHANNELS)
		peer = enet
	else:
		var ws := _websocket()
		# A whole address ("wss://host:443": the browser build to a lobby server).
		var url := address if address.contains("://") else "ws://%s:%d" % [address, port]
		err = ws.create_client(url)
		peer = ws
	if err != OK:
		peer = null
		return false
	_wire()
	return true


func _wire() -> void:
	_dice.seed = 1997
	peer.peer_connected.connect(
		func(id: int) -> void:
			joined.append(id)
			_peers[id] = true
			_patient(id)
	)
	peer.peer_disconnected.connect(
		func(id: int) -> void:
			_peers.erase(id)
			if _claimed.has(id):
				_claimed.erase(id)
				tap.gone(self, id)
			else:
				left.append(id)
	)


## A peer is given up on only after PATIENCE_MS of silence: a machine loading
## a map or compiling shaders can stall for a few seconds (ENet's own floor is
## five).
func _patient(id: int) -> void:
	if peer is ENetMultiplayerPeer:
		var other := (peer as ENetMultiplayerPeer).get_peer(id)
		if other != null:
			other.set_timeout(32, PATIENCE_MS, PATIENCE_MS * 3)
			if not throttle:
				# ENet drops unreliable packets while the round trip grows (its
				# throttle falls to 1 in 32 and climbs back slowly): with a
				# wandering round trip it threw away a third to over half of
				# the inputs, which the host then held or merged. Ours are
				# small and carried again: the throttle is set to come back
				# whole at the next steady answer.
				other.throttle_configure(THROTTLE_INTERVAL, THROTTLE_BACK, 0)


func connected() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## This side's peer id (the host is HOST_ID).
func id() -> int:
	return peer.get_unique_id() if peer != null else 0


## Why this session was turned away before it was through ("" not): a
## RelayLink's refusal (no such code, the party line full).
func refusal() -> String:
	return ""


## Milliseconds the far side adds past this link's own round trip (a
## RelayLink: the host's trip to the party line).
func extra_ms() -> float:
	return 0.0


## Round trip to peer `to` in ms (-1: not known, a WebSocket).
func rtt(to: int) -> float:
	if peer is ENetMultiplayerPeer:
		var other := (peer as ENetMultiplayerPeer).get_peer(to)
		if other != null:
			return other.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	return -1.0


## Peer `to`'s address as this side sees it ("" not known).
func address_of(to: int) -> String:
	if peer is ENetMultiplayerPeer:
		var other := (peer as ENetMultiplayerPeer).get_peer(to)
		return other.get_remote_address() if other != null else ""
	if peer is WebSocketMultiplayerPeer and _peers.has(to):
		return (peer as WebSocketMultiplayerPeer).get_peer_address(to)
	return ""


## The party line takes peer `to` as its own (or gives it back).
func claim(to: int, on := true) -> void:
	if on:
		_claimed[to] = true
	else:
		_claimed.erase(to)


func claimed(to: int) -> bool:
	return _claimed.has(to)


## [joined, left] since the last call.
func take_events() -> Array:
	var out := [joined.duplicate(), left.duplicate()]
	joined.clear()
	left.clear()
	if also != null:
		var more := also.take_events()
		for i in 2:
			var dst: Array = out[i]
			for id: int in more[i]:
				dst.append(id + ALSO_IDS)
	return out


## Sends `bytes` to peer `to` (0: everyone) on `channel`: CH_RELIABLE is
## reliable, the others unreliable unless the packet is over MTU_SAFE.
func send(to: int, channel: int, bytes: PackedByteArray) -> void:
	if also != null and (to == 0 or to >= ALSO_IDS):
		also.send(maxi(0, to - ALSO_IDS), channel, bytes)
		if to != 0:
			return
	if peer == null:
		return
	if to == 0 and not _claimed.is_empty():
		# The party line's peers hear nothing of this session's own.
		for other: int in _peers.keys():
			if not _claimed.has(other):
				send(other, channel, bytes)
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
	if reliable and resend_lost and loss > 0.0 and _dice.randf() < loss:
		# A reliable packet the network loses comes a retransmit timeout
		# later (ENet: about the round trip and four times its spread), and
		# everything after it on its channel waits for it (below): the
		# head-of-line stall a reliable snapshot stream suffers.
		due += lag_ms * 2.0 + jitter_ms * 2.0 + RESEND_MS
		resent += 1
	if reliable:
		# Reliable packets keep their order whatever the jitter.
		var last_due: float = _last_due.get(channel, 0.0)
		due = maxf(due, last_due)
		_last_due[channel] = due
	_queue.append([due, to, channel, reliable, bytes])


func _put(to: int, channel: int, reliable: bool, bytes: PackedByteArray) -> void:
	if peer == null or (to != 0 and not _peers.has(to)):
		return  # gone meanwhile (a packet the test's lag held back)
	if hosting and to != 0 and peer is ENetMultiplayerPeer:
		# Hanging up already (its goodbye not yet polled): ENet refuses it.
		var other := (peer as ENetMultiplayerPeer).get_peer(to)
		if other == null or other.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return
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
			var due: float = item[0]
			if due <= now_ms:
				var to: int = item[1]
				var channel: int = item[2]
				var reliable: bool = item[3]
				var bytes: PackedByteArray = item[4]
				_put(to, channel, reliable, bytes)
			else:
				keep.append(item)
		_queue = keep
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return []
	peer.poll()
	var out: Array = []
	while peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var channel := peer.get_packet_channel() if tap != null else 0
		var bytes := peer.get_packet()
		received += bytes.size()
		received_packets += 1
		if (
			tap != null
			and (_claimed.has(from) or (not bytes.is_empty() and bytes[0] >= NetWire.RELAY_FIRST))
		):
			tap.take(self, from, bytes, channel)
			continue
		out.append([from, bytes])
	if also != null:
		for packet: Array in also.poll(now_ms):
			var from: int = packet[0]
			out.append([from + ALSO_IDS, packet[1]])
	return out


## Lets one peer go (the host turning a client away or kicking it).
func drop(id: int) -> void:
	if also != null and id >= ALSO_IDS:
		also.drop(id - ALSO_IDS)
		return
	if _claimed.has(id):
		return  # the party line's (it lets its own go: cut())
	# (A server list's knock may have hung up first: only a peer still here.)
	if peer != null and hosting and _peers.has(id):
		peer.disconnect_peer(id)
	_peers.erase(id)


## The party line letting one of its peers go (its goodbye had its time).
func cut(id: int) -> void:
	if peer != null and hosting and _peers.has(id):
		peer.disconnect_peer(id)


## Sends what was put out this frame now, not at the next poll (the party
## line forwards into other sessions than the one it read from).
func flush() -> void:
	if peer is ENetMultiplayerPeer:
		var host_of := (peer as ENetMultiplayerPeer).host
		if host_of != null:
			host_of.flush()
	elif peer != null:
		peer.poll()


func close() -> void:
	if also != null:
		also.close()
		also = null
	if peer != null:
		peer.close()
		peer = null


## A WebSocket peer with room for a whole snapshot in one message.
static func _websocket() -> WebSocketMultiplayerPeer:
	var ws := WebSocketMultiplayerPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 1 << 20
	return ws
