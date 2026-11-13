## The authoritative host of a network game: runs a chapter with no renderer
## work, HUD, sound or presentation at all (a Game made with host on: no
## looks-only features, a QuietSound, no voices or talk), one fixed 120 Hz
## tick at a time from every player's controls, and hands out what clients
## need to keep up: a whole snapshot, or what changed since the tick a client
## last acknowledged (net_track.gd finds it field by field).
##
##   var host := GameHost.new("fair", 2, {"difficulty": 1})
##   host.step({0: controls_one, 1: controls_two})   # a slot left out stands idle
##   var full := host.snapshot()                     # bytes: {"tick", "full"}
##   var d := host.delta_since(acked)                # bytes: {"tick", "base", "d"}
##                                                   # (or a full one when the
##                                                   # base is too old)
##   var mirror := GameHost.mirror_for(client_game)  # game_mirror.gd
##   mirror.take(full); mirror.take(d)               # the client keeps up
##
## The transport (who sends which bytes to whom) is not here. A host game and
## an ordinary game fed the same controls stay identical (tools/net_check.gd).
class_name GameHost
extends RefCounted

## One tick, as the game's own fixed step (main_state.gd SIM_STEP).
const STEP := 1.0 / 120.0
## How often a client gets a delta, in ticks (30 Hz).
const DELTA_EVERY := 4
## How many ticks back a client's acknowledged base may be and still get a
## delta (older: a whole snapshot instead).
const HISTORY := 240

## Every host in the program shares the art index (the level needs it).
static var _art: Assets = null

var game: Game
var tick := 0
var track: NetTrack
## What changed at each tick the host looked at (oldest first): [tick, delta].
var _log: Array = []
var _looked_at := -1
## The look before the oldest change in the log: the oldest base it can serve.
var _base_tick := 0
## Milliseconds the last step, delta and snapshot took (the server prints them).
var step_ms := 0.0
var delta_ms := 0.0


## A host for `level_id` with `slots` players (the second on a step off the
## first, where the floor is open), configured with `options` (difficulty...).
## `existing`: adopt a game already made instead (adopt()).
func _init(level_id := "hickston", slots := 1, options := {}, existing: Game = null) -> void:
	if existing != null:
		game = existing
	else:
		if _art == null:
			_art = Assets.new()
		game = Game.new(_art, null, QuietSound.new(), level_id, true)
		game.configure(options)
		for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(level_id))):
			game.history.append([done, 1, 2, 0, 1, 60])
		for i in slots - 1:
			add_player()
	track = NetTrack.new(game)
	_looked_at = tick
	_base_tick = tick


## A host over a game already made (and perhaps already played).
static func adopt(existing: Game) -> GameHost:
	return GameHost.new("", 0, {}, existing)


## A mirror keeping `client` (a Game of the same level, fresh or running) up
## with a host.
static func mirror_for(client: Game) -> GameMirror:
	return GameMirror.new(client)


## Adds a player a step off player one where the floor is open; their slot.
func add_player() -> int:
	return join_near(game)


## Adds a player to `g` a step off player one where the floor is open (the
## next slot a little further, turned a little more); their slot.
static func join_near(g: Game) -> int:
	var game := g
	var p: Player = game.players[0]
	var at := Vector2(p.x, p.y)
	var n := game.players.size()
	for side: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
		var there := Vector2(p.x, p.y) + side * (1.2 + (n - 1) * .3)
		if not game.world.blocked(there.x, there.y, .25):
			at = there
			break
	return Players.join(game, at.x, at.y, p.angle + .5 * n).slot


## One tick: `controls` maps slot -> Game.Controls (a slot left out stands idle).
func step(controls: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	game.tick(STEP, controls)
	tick += 1
	step_ms = (Time.get_ticks_usec() - t0) / 1000.0


## The whole state now, as bytes: {"tick", "full": GameSnapshot.capture()}.
func snapshot() -> PackedByteArray:
	_look()
	return GameSnapshot.to_bytes({"tick": tick, "full": GameSnapshot.capture(game)})


## What changed since `acked` (a tick whose snapshot or delta a client has
## put on), as bytes: {"tick", "base": acked, "d": delta}; a whole snapshot
## when `acked` is older than the host remembers (or -1: none yet).
func delta_since(acked: int) -> PackedByteArray:
	var t0 := Time.get_ticks_usec()
	_look()
	var out := PackedByteArray()
	var merged = _since(acked)
	if merged == null:
		out = snapshot()
	else:
		out = GameSnapshot.to_bytes({"tick": tick, "base": acked, "d": merged})
	delta_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return out


## The delta since `acked` as a Dictionary, or null when it cannot be made: a
## base the host no longer remembers (every tick a client can hold is one the
## host looked at: snapshot() and delta_since() look first).
func _since(acked: int):
	if acked < _base_tick or acked > tick:
		return null
	var merged = {}
	for row: Array in _log:
		if int(row[0]) <= acked:
			continue
		merged = GameSnapshot.merge(merged, row[1])
		if merged == null:
			return null
	return merged


## Looks for what changed since the last look (once a tick at most).
func _look() -> void:
	if _looked_at == tick:
		return
	var change := track.changes()
	_log.append([tick, change])
	_looked_at = tick
	while not _log.is_empty() and int(_log[0][0]) < tick - HISTORY:
		_base_tick = int(_log[0][0])
		_log.pop_front()
