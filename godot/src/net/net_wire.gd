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
##            client can step its own copy), then the GameSnapshot bytes
##   LOBBY    host -> clients, reliable: the lobby (its settings, the players)
##   ASK      client -> host, reliable: what this player wants (name, team,
##            ready)
##   START    host -> clients, reliable: the match begins (level, settings)
##   BACK     host -> clients, reliable: the match is over, back to the lobby
##   BYE      either way, reliable: leaving (with why: closed, kicked, full...)
##
## Controls go as CONTROL_BYTES: four halves (forward, strafe, turn, look),
## the buttons as bits (USE held and reload among them), then weapon, item,
## cycle, the 5v5 store's buy and the ticks the host rewound the shots by. The
## host plays what came out of these bytes, its own players' too, so every
## copy plays the same.
class_name NetWire
extends RefCounted

const PROTOCOL := 3
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
const NO_BASE := 0xFFFFFFFF
const CONTROL_BYTES := 14
## Inputs carried again in each INPUTS packet until confirmed.
const REDUNDANT := 12
const SNAP_HEADER := 22
const INPUTS_HEADER := 14
## The most ticks a shot is rewound by (a byte; the host's own cap is lower).
const MAX_REWIND := 255

# ------------------------------------------------------------------ controls


static func pack_controls(c) -> PackedByteArray:
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
static func quantized(c) -> Game.Controls:
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
	for at in [9, 10, 12]:
		if out.decode_s8(at) < 0 and skipped.decode_s8(at) >= 0:
			out.encode_s8(at, skipped.decode_s8(at))
	if out.decode_s8(11) == 0:
		out.encode_s8(11, skipped.decode_s8(11))
	for at in [4, 6]:
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
	var info = bytes_to_var(bytes.slice(1))
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


## SNAP. `echo` is [first tick, [per tick: slot byte + controls, ...]].
static func snap(
	seq: int, base: int, tick: int, input_ack: int, echo: Array, payload: PackedByteArray
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SNAP_HEADER)
	out[0] = SNAP
	out.encode_u32(1, seq)
	out.encode_u32(5, base & 0xFFFFFFFF)
	out.encode_u32(9, tick)
	out.encode_u32(13, input_ack & 0xFFFFFFFF)
	var ticks: Array = echo[1] if echo.size() > 1 else []
	out.encode_u32(17, int(echo[0]) if echo.size() > 0 else 0)
	out[21] = ticks.size()
	for row: PackedByteArray in ticks:
		out.append(row.size() / (CONTROL_BYTES + 1))
		out.append_array(row)
	out.append_array(payload)
	return out


## {seq, base (-1: whole), tick, input_ack (-1: none), echo_first, echo:
## [{slot: packed controls}], payload} of a SNAP packet (empty if malformed).
static func read_snap(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < SNAP_HEADER:
		return {}
	var base := bytes.decode_u32(5)
	var ack := bytes.decode_u32(13)
	var at := SNAP_HEADER
	var echo: Array = []
	for i in bytes[21]:
		if at >= bytes.size():
			return {}
		var count := bytes[at]
		at += 1
		if at + count * (CONTROL_BYTES + 1) > bytes.size():
			return {}
		var row := {}
		for k in count:
			row[int(bytes[at])] = bytes.slice(at + 1, at + 1 + CONTROL_BYTES)
			at += CONTROL_BYTES + 1
		echo.append(row)
	return {
		"seq": bytes.decode_u32(1),
		"base": -1 if base == NO_BASE else base,
		"tick": bytes.decode_u32(9),
		"input_ack": -1 if ack == 0xFFFFFFFF else ack,
		"echo_first": bytes.decode_u32(17),
		"echo": echo,
		"payload": bytes.slice(at),
	}


## The inputs every player played on one tick: slot byte + controls each.
static func tick_row(by_slot: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	var slots := by_slot.keys()
	slots.sort()
	for slot in slots:
		out.append(int(slot))
		out.append_array(by_slot[slot])
	return out
