## Voice chat on the wire (docs/dev/multiplayer.md "Voice chat"): every
## online lobby's NetPlay has one (`net.voice`).
##
## A talker's frames (voice_codec.gd, 40 ms each) go up to whoever runs the
## lobby on their own unreliable channel (NetSession.CH_VOICE), so they never
## hold up the game's packets. The host (a player's own lobby, the lobby
## server, or a lobby through the party line: the line only passes bytes)
## sends each frame on only to the players within RADIUS of the talker in
## the match it already plays, never back to the talker, and at most
## HEARD_MOST voices to one player. It never decodes, keeps or writes a frame.
##
## Who hears whom:
## - In the lobby, everyone in it hears everyone, flat (no places yet).
## - In a match, a player hears whoever stands within RADIUS (walls muffle
##   them on the listener's side, as the game's sounds do).
## - In the 5v5 round modes the dead watch their team till the round ends:
##   they hear the living near where they fell or near a living teammate (the
##   one they watch is one of those), but only the dead hear the dead (flat),
##   so nobody calls out from the grave. In co-op, deathmatch and a
##   COUNTY RUN death is short and everyone talks as the living do.
## - A player with VOICE CHAT off is sent nothing; one muted by a listener
##   is not sent to that listener (ASK "voice", "mutes").
##
## Packets (first byte NetWire.VOICE):
##   up    talker -> host: VOICE, seq (u16), flags, frame
##   down  host -> listener: VOICE, seq (u16), flags, the talker's id (u32;
##         a lobby's second session's ids keep their top bit), frame
## flags: END (the talker let go), FLAT (no place: the lobby, or the dead to
## the dead).
##
## A listener keeps a Talker for each voice: a small jitter buffer by
## sequence (START_FRAMES before it plays, MOST_FRAMES at most), a lost frame
## covered by the last one fading (twice at most), late ones dropped.
class_name NetVoice
extends RefCounted

const VOICE_DATA := "res://data/tuning/voice.cfg"
const END := 1
const FLAT := 2
const UP_HEADER := 4
const DOWN_HEADER := 8

static var RADIUS: float = Tuning.file(VOICE_DATA).get_value("voice", "radius", 18.0)
static var HEARD_MOST: int = Tuning.file(VOICE_DATA).get_value("voice", "heard_most", 4)
static var FRAMES_A_SECOND: float = Tuning.file(VOICE_DATA).get_value(
	"voice", "frames_a_second", 30.0
)
static var FRAMES_BURST: float = Tuning.file(VOICE_DATA).get_value("voice", "frames_burst", 10.0)
static var START_FRAMES: int = Tuning.file(VOICE_DATA).get_value("voice", "start_frames", 2)
static var START_MS: float = Tuning.file(VOICE_DATA).get_value("voice", "start_ms", 90.0)
static var MOST_FRAMES: int = Tuning.file(VOICE_DATA).get_value("voice", "most_frames", 8)
static var TALKING_MS: float = Tuning.file(VOICE_DATA).get_value("voice", "talking_ms", 260.0)
## A voice a listener hears keeps its place this long after its last frame
## (HEARD_MOST counts the voices inside it).
const HOLD_MS := 400.0
const SWEEP_MS := 10000.0
## The last time any lobby in this process passed a frame on (the lobby
## server wakes sooner while voices are going: LobbyServer._rest).
static var last_forward := -1.0e9

## The host's side: when each listener last got each voice ({listener:
## {talker: ms}}), each talker's frame allowance ([tokens, ms]).
var _heard := {}
var _allowance := {}
## Something was sent on since the last flush (NetPlay.poll flushes it),
## and when the routing and the voices were last swept.
var _sent := false
var _swept := 0.0
## A listener's side: id -> Talker.
var talkers := {}
## Ids this player will not hear (the lobby's MUTE), and VOICE CHAT on.
var muted := {}
var hearing := true
## Our mic as voice_chat.gd last found it ("off", "on", "none", "asking",
## "refused"), for the lobby's own row.
var mic := "off"
## Our own frames' sequence, and when we last sent one (our own mark).
var seq := 0
var sent_at := -1.0e9
## What the host was last told of our hearing and mutes (Client: ASK).
var _told := ""
## Counts: frames and bytes up, frames passed on and their bytes, the
## host's time spent routing (us), frames dropped as too many or too fast.
var frames_up := 0
var bytes_up := 0
var forwarded := 0
var forwarded_bytes := 0
var route_us := 0
var refused := 0


## One voice as a listener hears it: the jitter buffer and what it plays.
class Talker:
	extends RefCounted
	var id := 0
	var frames := {}
	var next := -1
	var playing := false
	var flat := false
	var heard_at := -1.0e9
	var first_at := -1.0e9
	var last_pcm := PackedFloat32Array()
	var queue := PackedFloat32Array()
	var covered := 0
	## Frames that came, came too late, were covered for, were thrown to catch up.
	var got := 0
	var late := 0
	var lost := 0
	var skipped := 0

	func push(at: int, frame: PackedByteArray, flags: int, now: float) -> void:
		if playing and NetVoice.ahead(at, next) < 0:
			late += 1
			return
		if frames.is_empty() and not playing:
			first_at = now
		frames[at] = frame
		got += 1
		heard_at = now
		flat = flags & NetVoice.FLAT != 0
		while frames.size() > NetVoice.MOST_FRAMES:
			# Too far behind (a stall, a WebSocket's burst): the oldest go.
			var oldest := _oldest()
			frames.erase(oldest)
			skipped += 1
			if playing:
				next = _oldest()
				covered = 0

	func talking(now: float) -> bool:
		return now - heard_at < NetVoice.TALKING_MS

	## `count` samples at VoiceCodec.RATE, fewer (or none) when it runs dry.
	func pull(count: int, now: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		if not playing:
			var ready := frames.size() >= NetVoice.START_FRAMES
			if frames.is_empty() or (not ready and now - first_at < NetVoice.START_MS):
				return out
			playing = true
			next = _oldest()
			covered = 0
		while out.size() < count:
			if queue.is_empty() and not _next_frame():
				playing = false
				next = -1
				break
			var take := mini(count - out.size(), queue.size())
			out.append_array(queue.slice(0, take))
			queue = queue.slice(take)
		return out

	func _next_frame() -> bool:
		if frames.has(next):
			var frame: PackedByteArray = frames[next]
			queue = VoiceCodec.decode(frame)
			frames.erase(next)
			last_pcm = queue
			covered = 0
			next = (next + 1) & 0xFFFF
			return not queue.is_empty()
		if frames.is_empty():
			return false
		if covered < 2 and not last_pcm.is_empty():
			# A frame lost on the way: the last one again, fading.
			var gain := .5 if covered == 0 else .2
			queue = last_pcm.duplicate()
			var n := queue.size()
			for i in n:
				queue[i] *= gain * (1.0 - float(i) / n * .5)
			covered += 1
			lost += 1
			next = (next + 1) & 0xFFFF
			return true
		next = _oldest()
		covered = 0
		return _next_frame()

	func _oldest() -> int:
		var best := -1
		for k: int in frames.keys():
			if best < 0 or NetVoice.ahead(k, best) < 0:
				best = k
		return best


## How far sequence `a` is past `b` (negative: before it), across the wrap.
static func ahead(a: int, b: int) -> int:
	return ((a - b + 32768) & 0xFFFF) - 32768


## An id as four bytes (a lobby's second session's ids, past
## NetSession.ALSO_IDS, keep the top bit) and back.
static func wire_id(id: int) -> int:
	return (id - NetSession.ALSO_IDS) | 0x80000000 if id >= NetSession.ALSO_IDS else id


static func id_of_wire(wire: int) -> int:
	return (wire & 0x7FFFFFFF) + NetSession.ALSO_IDS if wire & 0x80000000 else wire


# ------------------------------------------------------------------ sending


## Our own frame (VoiceCodec.BYTES) going out: to the host, or (we host)
## straight to whoever hears us. `end`: the last of what we said.
func send_own(net: NetPlay, frame: PackedByteArray, end: bool, now: float) -> void:
	if net.session == null or frame.size() != VoiceCodec.BYTES:
		return
	var packet := PackedByteArray([NetWire.VOICE, seq & 0xFF, seq >> 8, END if end else 0])
	packet.append_array(frame)
	seq = (seq + 1) & 0xFFFF
	sent_at = now
	frames_up += 1
	bytes_up += packet.size()
	if net.role == NetPlay.Role.HOST:
		_route(net, net.my_id, packet, now)
	else:
		net.session.send(NetSession.HOST_ID, NetSession.CH_VOICE, packet)


## Whether we sent a frame lately (our own mark).
func sending(now: float) -> bool:
	return now - sent_at < TALKING_MS


## Tells the host whether we hear voices and whom we muted (when it changed;
## the host itself only notes it).
func tell(net: NetPlay) -> void:
	var mutes: Array = muted.keys()
	mutes.sort()
	var said := "%s %s" % [hearing, mutes]
	if said == _told or net.session == null:
		return
	if net.role == NetPlay.Role.CLIENT and net.phase not in ["lobby", "match"]:
		return
	_told = said
	var want := {"voice": hearing, "mutes": mutes}
	if net.role == NetPlay.Role.HOST:
		var me := net.player_of(net.my_id)
		me.merge(want, true)
	else:
		net.ask(want)


## What a player's ASK said of their voice chat, noted on their lobby
## entry `p` (NetPlay; read by listeners()): VOICE CHAT on, whom they muted.
static func note(p: Dictionary, info: Dictionary) -> void:
	var hears: bool = info["voice"]
	var mutes: Array = info.get("mutes", []) if info.get("mutes") is Array else []
	p["voice"] = hears
	p["mutes"] = mutes.slice(0, Modes.MAX_PLAYERS)


## Mutes or unmutes player `id` for us.
func toggle_mute(net: NetPlay, id: int) -> void:
	if id == net.my_id:
		return
	if muted.has(id):
		muted.erase(id)
	else:
		muted[id] = true
		talkers.erase(id)
	tell(net)


# ------------------------------------------------------------------ taking


## A VOICE packet from `from`: the host routes it, a listener plays it.
func take(net: NetPlay, from: int, bytes: PackedByteArray, now: float) -> void:
	if net.role == NetPlay.Role.HOST:
		if bytes.size() == UP_HEADER + VoiceCodec.BYTES and _allowed(from, now):
			_route(net, from, bytes, now)
		else:
			refused += 1
		return
	if bytes.size() != DOWN_HEADER + VoiceCodec.BYTES:
		return
	var who := id_of_wire(bytes.decode_u32(4))
	_hear(net, who, bytes.decode_u16(1), bytes[3], bytes.slice(DOWN_HEADER), now)


## Sends what was routed this poll at once (the lobby server would hold it
## to its next wake), and now and then forgets those who left.
func flush(net: NetPlay, now: float) -> void:
	if _sent and net.session != null:
		net.session.flush()
	_sent = false
	if now - _swept > SWEEP_MS:
		_swept = now
		sweep(net, now)


## A talker's allowance: FRAMES_A_SECOND, FRAMES_BURST at once.
func _allowed(from: int, now: float) -> bool:
	var had: Array = _allowance.get(from, [FRAMES_BURST, now])
	var kept: float = had[0]
	var since: float = had[1]
	var tokens := minf(FRAMES_BURST, kept + (now - since) * FRAMES_A_SECOND / 1000.0)
	if tokens < 1.0:
		_allowance[from] = [tokens, now]
		return false
	_allowance[from] = [tokens - 1.0, now]
	return true


func _route(net: NetPlay, from: int, packet: PackedByteArray, now: float) -> void:
	var began := Time.get_ticks_usec()
	var flags := packet[3] & END
	var frame := packet.slice(UP_HEADER)
	for heard: Array in listeners(net, from):
		var to: int = heard[0]
		var flat: bool = heard[1]
		if not _room_for(to, from, now):
			continue
		var f := flags | (FLAT if flat else 0)
		if to == net.my_id:
			_hear(net, from, packet.decode_u16(1), f, frame, now)
			continue
		var out := PackedByteArray([NetWire.VOICE, packet[1], packet[2], f, 0, 0, 0, 0])
		out.encode_u32(4, wire_id(from))
		out.append_array(frame)
		net.session.send(to, NetSession.CH_VOICE, out)
		forwarded += 1
		forwarded_bytes += out.size()
		_sent = true
		last_forward = now
	route_us += Time.get_ticks_usec() - began


## Whether `to` may be sent `from`'s voice now: it already hears it, or it
## hears fewer than HEARD_MOST.
func _room_for(to: int, from: int, now: float) -> bool:
	var got: Dictionary = _heard.get(to, {})
	var last: float = got.get(from, -1.0e9)
	if now - last >= HOLD_MS:
		var others := 0
		for k: int in got.keys():
			var at: float = got[k]
			if now - at < HOLD_MS:
				others += 1
			else:
				got.erase(k)
		if others >= HEARD_MOST:
			_heard[to] = got
			return false
	got[from] = now
	_heard[to] = got
	return true


## Who hears `from` now: [[id, flat], ...] (never `from` itself; the host
## itself when it plays and hears).
func listeners(net: NetPlay, from: int) -> Array:
	var out: Array = []
	var talker := net.player_of(from)
	if talker.is_empty():
		return out
	var g: Game = net.match_game() if net.phase == "match" else null
	var spot := _spot(g, talker)
	for p: Dictionary in net.players:
		var to: int = p["id"]
		if to == from:
			continue
		var hears: bool = p.get("voice", true)
		var mutes: Array = p.get("mutes", [])
		if not hears or mutes.has(from):
			continue
		if g == null:
			out.append([to, true])
			continue
		var ear := _spot(g, p)
		if spot.w < 0.0:
			# The dead (or someone with no place in the match) reach the dead only.
			if ear.w < 0.0:
				out.append([to, true])
			continue
		var at := Vector3(spot.x, spot.y, spot.z)
		if at.distance_to(Vector3(ear.x, ear.y, ear.z)) <= RADIUS:
			out.append([to, false])
		elif ear.w < 0.0 and _near_mate(g, p, at):
			# The dead watch their living teammates: they hear what those hear.
			out.append([to, false])
	return out


## Whether a living teammate of lobby player `p` stands within RADIUS of `at`.
func _near_mate(g: Game, p: Dictionary, at: Vector3) -> bool:
	var slot: int = p.get("slot", -1)
	if slot < 0 or slot >= g.players.size():
		return false
	var team := g.players[slot].team
	for q: Player in g.players:
		if q.slot != slot and q.team == team and q.health > 0 and not q.away:
			if at.distance_to(Vector3(q.x, q.y, q.floor_z)) <= RADIUS:
				return true
	return false


## Where a lobby player stands in match `g`: x, y, the floor, and w 1 in
## play, -1 out of it (no place in the match, gone, or dead in a round mode).
func _spot(g: Game, p: Dictionary) -> Vector4:
	if g == null:
		return Vector4(0, 0, 0, 1)
	var slot: int = p.get("slot", -1)
	if slot < 0 or slot >= g.players.size():
		return Vector4(0, 0, 0, -1)
	var q: Player = g.players[slot]
	var gone := q.away or (q.health <= 0 and Modes.is_tactical(g))
	return Vector4(q.x, q.y, q.floor_z, -1 if gone else 1)


func _hear(net: NetPlay, who: int, at: int, flags: int, frame: PackedByteArray, now: float) -> void:
	if not hearing or muted.has(who) or who == net.my_id:
		return
	var t: Talker = talkers.get(who)
	if t == null:
		t = Talker.new()
		t.id = who
		talkers[who] = t
	t.push(at, frame, flags, now)


## Whether player `id` is talking (as we hear them; ourselves: sending).
func talking(id: int, my_id: int, now: float) -> bool:
	if id == my_id:
		return sending(now)
	var t: Talker = talkers.get(id)
	return t != null and t.talking(now)


## Forgets voices gone quiet for long (their players left).
func sweep(net: NetPlay, now: float) -> void:
	for id: int in talkers.keys():
		var t: Talker = talkers[id]
		if now - t.heard_at > 5000.0 and not t.playing:
			talkers.erase(id)
	for id: int in _heard.keys():
		if net.player_of(id).is_empty():
			_heard.erase(id)
			_allowance.erase(id)
