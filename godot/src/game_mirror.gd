## A client's side of a network game: keeps a Game (of the host's level, just
## made or already running and drawn) the same as the host's, from the bytes
## GameHost hands out (game_host.gd). A whole snapshot is put on as it is
## (GameSnapshot.apply); a delta only when it was made against the tick this
## mirror holds, and then only the fields it touches (GameSnapshot.apply_delta).
## `acked` is the tick to acknowledge to the host.
##
##   var mirror := GameMirror.new(client_game)
##   mirror.take(bytes)      # true when put on; false: stale or for another base
##
## The mirror does not tick its game (the host does the playing); the game is
## drawn and heard from what it was given. Prediction is not here.
class_name GameMirror
extends RefCounted

var game: Game
## The host tick this game now matches (-1: nothing taken yet).
var acked := -1
## The whole snapshot at `acked` (deltas are laid over it).
var full := {}
## Milliseconds the last take() spent.
var take_ms := 0.0


func _init(p_game: Game) -> void:
	game = p_game


## Puts the host's bytes (snapshot() or delta_since()) on the game. False when
## they are older than what it holds, made against another tick, or for
## another level.
func take(bytes: PackedByteArray) -> bool:
	var t0 := Time.get_ticks_usec()
	var ok := take_data(GameSnapshot.from_bytes(bytes))
	take_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return ok


func take_data(data: Dictionary) -> bool:
	var tick := int(data.get("tick", -1))
	if tick < 0 or tick <= acked and acked >= 0 and data.has("d"):
		return false
	if data.has("full"):
		if not GameSnapshot.apply(game, data["full"]):
			return false
		full = data["full"]
		acked = tick
		return true
	if not data.has("d") or int(data.get("base", -2)) != acked:
		return false
	var change: Dictionary = data["d"]
	full = GameSnapshot.patch_into(full, change)
	GameSnapshot.apply_delta(game, change, full)
	acked = tick
	return true
