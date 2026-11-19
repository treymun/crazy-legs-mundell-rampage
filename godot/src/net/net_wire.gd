## What goes in a network packet (net_session.gd carries them, net_sync.gd
## and net_play.gd use them). Each packet starts with its kind:
##
##   HELLO    client -> host, reliable: protocol, game version, name, password
##   WELCOME  host -> client, reliable: the client's slot, level and layout,
##            tick and snapshot rates (or why it was turned away)
##   INPUTS   client -> host, unreliable, every tick: the newest snapshot it
##            has (the ack), every input the host has not confirmed yet,
##            oldest first (up to REDUNDANT), so a lost packet costs nothing,
##            and the tick of the game it is showing (the host judges its
##            shots against the others as they stood then)
##   SNAP     host -> client: sequence, the base it is a delta from (NO_BASE:
##            whole), its tick, the last input of the client's it used, the
##            inputs every player played on each tick since the base (so the
##            client can step its own copy; packed, zstd), then the
##            GameSnapshot bytes. Unreliable, but a whole snapshot goes
##            reliable; one too big for a packet goes as SNAP_PARTs
##   SNAP_PART host -> client, unreliable: a piece of a SNAP too big for one
##            packet (seq, its place, how many); a piece lost loses that
##            snapshot only, never holding up the ones after it as a
##            reliable packet would
##   LOBBY    host -> clients, reliable: the lobby (its settings, the players)
##   ASK      client -> host, reliable: what this player wants (name, team,
##            ready)
##   START    host -> clients, reliable: the match begins (level, settings)
##   BACK     host -> clients, reliable: the match is over, back to the lobby
##   BYE      either way, reliable: leaving (with why: closed, kicked, full...)
##   MAP      host -> client, reliable: the lobby's player map (net_maps.gd)
##   VOICE    either way, unreliable on NetSession.CH_VOICE: a frame of voice
##            chat (net_voice.gd); an older side ignores it
##
## Controls go as CONTROL_BYTES: four halves (forward, strafe, turn, look),
## the buttons as bits (USE held and reload among them), then weapon, item,
## cycle, the 5v5 store's buy and the ticks the host rewound the shots by. The
## host plays what came out of these bytes, its own players' too, so every
## copy plays the same.
class_name NetWire
extends RefCounted

## 4: snapshot version 3 (a feature's guarded lists travel as tables).
## 5: a SNAP's echoed inputs packed, a big SNAP in SNAP_PARTs (pass 12).
const PROTOCOL := 5
const HELLO := 1
const WELCOME := 2
const INPUTS := 3
const SNAP := 4
const LOBBY := 5
const ASK := 6
const START := 7
const BACK := 8
const BYE := 9
## A server list's knock (net_browser.gd) and the lobby's answer (NetPlay.summary).
const INFO := 10
## COUNTY RUN's daily board (county_board.gd): a post or an ask, and the board.
const BOARD := 11
const SNAP_PART := 12
## Voice chat (net_voice.gd).
const VOICE := 13
## A lobby's player map (net_maps.gd).
const MAP := 20
## The party line's own kinds start here (net_relay.gd): a game packet's
## first byte stays below it.
const RELAY_FIRST := 0xF0
const NO_BASE := 0xFFFFFFFF
const CONTROL_BYTES := 14
## Inputs carried again in each INPUTS packet until confirmed.
const REDUNDANT := 12
## A SNAP: kind, seq, base, tick, input ack, echo's first tick (u32 each),
## the rows, the rows' size unpacked and packed (u16 each; packed 0: kept
## as they are).
const SNAP_HEADER := 26
## A SNAP_PART: kind, the snapshot's seq (u32), its place, how many.
const PART_HEADER := 7
## A SNAP over this goes in parts: room for the party line's own header
## (NetRelay.TO_HEADER) under NetSession.MTU_SAFE, so a part never goes
## reliable on the way.
const PART_MOST := 1184
const PARTS_MOST := 64
## Off: a SNAP's rows go as they are (net_lag.gd's `old`, for the sizes).
static var pack_rows := true
const INPUTS_HEADER := 14
## The most ticks a shot is rewound by (a byte; the host's own cap is lower).
const MAX_REWIND := 255

# ------------------------------------------------------------------ controls


static func pack_controls(c: Game.Controls) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(CONTROL_BYTES)
	out.encode_half(0, c.forward)
	out.encode_half(2, c.strafe)
	out.encode_half(4, c.turn)
	out.encode_half(6, c.look)
	var bits := 0
	for i in 8:
		if [c.running, c.fire, c.alt_fire, c.jump, c.crouch, c.use, c.hold, c.reload][i]:
			bits |= 1 << i
	out[8] = bits
	out.encode_s8(9, clampi(c.weapon, -128, 127))
	out.encode_s8(10, clampi(c.item, -128, 127))
	out.encode_s8(11, clampi(c.cycle, -128, 127))
	out.encode_s8(12, clampi(c.buy, -128, 127))
	out[13] = clampi(c.rewind, 0, MAX_REWIND)
	return out


static func unpack_controls(bytes: PackedByteArray, at := 0) -> Game.Controls:
	var c := Game.Controls.new()
	c.forward = bytes.decode_half(at)
	c.strafe = bytes.decode_half(at + 2)
	c.turn = bytes.decode_half(at + 4)
	c.look = bytes.decode_half(at + 6)
	var bits := bytes[at + 8]
	c.running = bits & 1 != 0
	c.fire = bits & 2 != 0
	c.alt_fire = bits & 4 != 0
	c.jump = bits & 8 != 0
	c.crouch = bits & 16 != 0
	c.use = bits & 32 != 0
	c.hold = bits & 64 != 0
	c.reload = bits & 128 != 0
	c.weapon = bytes.decode_s8(at + 9)
	c.item = bytes.decode_s8(at + 10)
	c.cycle = bytes.decode_s8(at + 11)
	c.buy = bytes.decode_s8(at + 12)
	c.rewind = bytes[at + 13]
	return c


## Controls as they come out of the wire (what every copy of the game plays).
static func quantized(c: Game.Controls) -> Game.Controls:
	return unpack_controls(pack_controls(c))


## The same held controls without the one-shot actions (USE, reload, a gun, an
## item, a cycle, a buy): what the host plays again when a client's input is
## late. The turn and look go too: a mouse moves once.
static func held_only(bytes: PackedByteArray) -> PackedByteArray:
	var out := bytes.duplicate()
	out[8] = out[8] & ~(32 | 128)
	out.encode_half(4, 0.0)
	out.encode_half(6, 0.0)
	out.encode_s8(9, -1)
	out.encode_s8(10, -1)
	out.encode_s8(11, 0)
	out.encode_s8(12, -1)
	return out


## `later` with the one-shot actions of `skipped` kept (an input the host
## drops to catch up must not lose a USE press, a buy or a mouse turn).
static func merged(skipped: PackedByteArray, later: PackedByteArray) -> PackedByteArray:
	var out := later.duplicate()
	out[8] = out[8] | (skipped[8] & (32 | 128))
	for at: int in [9, 10, 12]:
		if out.decode_s8(at) < 0 and skipped.decode_s8(at) >= 0:
			out.encode_s8(at, skipped.decode_s8(at))
	if out.decode_s8(11) == 0:
		out.encode_s8(11, skipped.decode_s8(11))
	for at: int in [4, 6]:
		out.encode_half(at, out.decode_half(at) + skipped.decode_half(at))
	return out


## `bytes` with the host's rewind put in (ticks back its shots are judged).
static func with_rewind(bytes: PackedByteArray, ticks: int) -> PackedByteArray:
	var out := bytes.duplicate()
	out[13] = clampi(ticks, 0, MAX_REWIND)
	return out


# ------------------------------------------------------------------ messages


static func hello(game_version: String, extra := {}) -> PackedByteArray:
	var info := {"protocol": PROTOCOL, "version": game_version}
	info.merge(extra)
	return message(HELLO, info)


static func welcome(info: Dictionary) -> PackedByteArray:
	return message(WELCOME, info)


## A reliable message of `kind` carrying a dictionary of plain values.
static func message(kind: int, info: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([kind])
	out.append_array(var_to_bytes(info))
	return out


## A message's dictionary (empty when it is malformed).
static func info_of(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {}
	var info: Variant = bytes_to_var(bytes.slice(1))
	return info if info is Dictionary else {}


## INPUTS: the newest snapshot the client has, then `list` (packed controls)
## starting at input `first`, and the tick of the game it is showing.
static func inputs(ack: int, first: int, list: Array, view_tick := -1) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(INPUTS_HEADER)
	out[0] = INPUTS
	out.encode_u32(1, ack & 0xFFFFFFFF)
	out.encode_u32(5, first)
	out[9] = list.size()
	out.encode_u32(10, view_tick & 0xFFFFFFFF)
	for bytes: PackedByteArray in list:
		out.append_array(bytes)
	return out


## {ack, first, list, view_tick} of an INPUTS packet (empty when malformed).
static func read_inputs(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < INPUTS_HEADER:
		return {}
	var count := bytes[9]
	if bytes.size() < INPUTS_HEADER + count * CONTROL_BYTES:
		return {}
	var list: Array = []
	for i in count:
		var at := INPUTS_HEADER + i * CONTROL_BYTES
		var one := bytes.slice(at, at + CONTROL_BYTES)
		one[13] = 0  # the rewind is the host's to set
		list.append(one)
	var ack := bytes.decode_u32(1)
	var view := bytes.decode_u32(10)
	return {
		"ack": -1 if ack == 0xFFFFFFFF else ack,
		"first": bytes.decode_u32(5),
		"list": list,
		"view_tick": -1 if view == 0xFFFFFFFF else view,
	}


## SNAP. `echo` is [first tick, [per tick: slot byte + controls, ...]]. The
## rows go zstd'd (a 5v5's 8 rows of 10 players, 1.2 KB, are about 200
## bytes packed: each player's controls change little from tick to tick).
static func snap(
	seq: int,
	base: int,
	tick: int,
	input_ack: int,
	echo: Array,
	payload: PackedByteArray,
	places: Array = []
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SNAP_HEADER)
	out[0] = SNAP
	out.encode_u32(1, seq)
	out.encode_u32(5, base & 0xFFFFFFFF)
	out.encode_u32(9, tick)
	out.encode_u32(13, input_ack & 0xFFFFFFFF)
	var ticks: Array = echo[1] if echo.size() > 1 else []
	var echo_seq: int = echo[0] if echo.size() > 0 else 0
	out.encode_u32(17, echo_seq)
	out[21] = ticks.size()
	var rows := PackedByteArray()
	for row: PackedByteArray in ticks:
		rows.append(row.size() / (CONTROL_BYTES + 1))
		rows.append_array(row)
	_put_places(rows, places, ticks.size())
	var packed := (
		rows.compress(FileAccess.COMPRESSION_ZSTD) if rows.size() > 32 and pack_rows else rows
	)
	out.encode_u16(22, rows.size())
	if packed.size() < rows.size():
		out.encode_u16(24, packed.size())
		out.append_array(packed)
	else:
		out.encode_u16(24, 0)
		out.append_array(rows)
	out.append_array(payload)
	return out


## A SNAP too big for one packet as SNAP_PARTs of PART_MOST bytes at most.
static func split(packet: PackedByteArray, seq: int) -> Array[PackedByteArray]:
	var room := PART_MOST - PART_HEADER
	var count := ceili(packet.size() / float(room))
	var out: Array[PackedByteArray] = []
	for i in count:
		var part := PackedByteArray()
		part.resize(PART_HEADER)
		part[0] = SNAP_PART
		part.encode_u32(1, seq)
		part[5] = i
		part[6] = count
		part.append_array(packet.slice(i * room, mini((i + 1) * room, packet.size())))
		out.append(part)
	return out


## {seq, base (-1: whole), tick, input_ack (-1: none), echo_first, echo:
## [{slot: packed controls}], payload} of a SNAP packet (empty if malformed).
## The start of one is enough for its rows (the first SNAP_PART of a big
## one: they come before the payload), which is all it reads then.
static func read_snap(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < SNAP_HEADER:
		return {}
	var base := bytes.decode_u32(5)
	var ack := bytes.decode_u32(13)
	var raw_size := bytes.decode_u16(22)
	var packed_size := bytes.decode_u16(24)
	var after := SNAP_HEADER + (packed_size if packed_size > 0 else raw_size)
	if after > bytes.size():
		return {}
	var rows := bytes.slice(SNAP_HEADER, after)
	if packed_size > 0:
		rows = rows.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
		if rows.size() != raw_size:
			return {}
	var at := 0
	var echo: Array = []
	for i in bytes[21]:
		if at >= rows.size():
			return {}
		var count := rows[at]
		at += 1
		if at + count * (CONTROL_BYTES + 1) > rows.size():
			return {}
		var row := {}
		for k in count:
			row[int(rows[at])] = rows.slice(at + 1, at + 1 + CONTROL_BYTES)
			at += CONTROL_BYTES + 1
		echo.append(row)
	var places := _read_places(rows, at, echo.size())
	at = after
	return {
		"seq": bytes.decode_u32(1),
		"base": -1 if base == NO_BASE else base,
		"tick": bytes.decode_u32(9),
		"input_ack": -1 if ack == 0xFFFFFFFF else ack,
		"echo_first": bytes.decode_u32(17),
		"echo": echo,
		"places": places,
		"payload": bytes.slice(at),
	}


## Where everyone stood on the last of the echoed ticks (game.place_log's
## rows, what a rewound shot needs: those not sent before), after the rows
## in the same packed block: a byte of how many ticks, then a tick each: a
## byte of floats and the float32s, each row's bits xored with the row
## before (they hardly change: the pack takes them down to a few bytes).
## Pass 12: a copy put back on a snapshot ahead of it lacked the ticks it
## skipped, and a shot rewound into them in the next second played
## otherwise. A reader that does not know them stops at the rows' end.
static func _put_places(rows: PackedByteArray, places: Array, ticks: int) -> void:
	if places.is_empty() or places.size() > ticks:
		return
	rows.append(places.size())
	var before := PackedInt32Array()
	for row: PackedFloat32Array in places:
		var bits := row.slice(0, 255).to_byte_array().to_int32_array()
		var put := bits.duplicate()
		if before.size() == bits.size():
			for k in bits.size():
				put[k] = bits[k] ^ before[k]
		rows.append(bits.size())
		rows.append_array(put.to_byte_array())
		before = bits


## The place rows of the last ticks of `ticks` echoed ([] none).
static func _read_places(rows: PackedByteArray, at: int, ticks: int) -> Array:
	if at >= rows.size():
		return []
	var n := rows[at]
	at += 1
	if n > ticks:
		return []
	var out: Array = []
	var before := PackedInt32Array()
	for i in n:
		if at >= rows.size():
			return []
		var count := rows[at]
		at += 1
		if at + count * 4 > rows.size():
			return []
		var bits := rows.slice(at, at + count * 4).to_int32_array()
		if before.size() == bits.size():
			for k in bits.size():
				bits[k] = bits[k] ^ before[k]
		before = bits
		out.append(bits.to_byte_array().to_float32_array())
		at += count * 4
	return out


## Who plays changing (pass 13): a row entry keyed EVENT_SLOT or past it
## carries a leave, a join or a new name instead of controls, on the tick
## the host made it, so every copy makes it before playing that tick as the
## host did (a leave and a join changed the host's game between ticks, and
## every other copy was put back once for each). CONTROL_BYTES: the kind,
## the player's slot, the name (ASCII, NetPlay.MAX_NAME at most). A copy of
## an older build reads it as controls for a slot nobody plays.
const EVENT_SLOT := 240
const EVENT_AWAY := 1
const EVENT_JOIN := 2
const EVENT_NAME := 3


static func event(kind: int, slot: int, name := "") -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(CONTROL_BYTES)
	out[0] = kind
	out[1] = clampi(slot, 0, 255)
	var text := name.to_ascii_buffer()
	for i in mini(text.size(), CONTROL_BYTES - 2):
		out[2 + i] = text[i]
	return out


## {"kind", "slot", "name"} of an event entry.
static func event_of(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < CONTROL_BYTES:
		return {}
	var text := bytes.slice(2, CONTROL_BYTES)
	var end := text.find(0)
	if end >= 0:
		text = text.slice(0, end)
	return {"kind": int(bytes[0]), "slot": int(bytes[1]), "name": text.get_string_from_ascii()}


## The inputs every player played on one tick: slot byte + controls each.
static func tick_row(by_slot: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	var slots := by_slot.keys()
	slots.sort()
	for slot: Variant in slots:
		var slot_n: int = slot
		var row: PackedByteArray = by_slot[slot]
		out.append(slot_n)
		out.append_array(row)
	return out
