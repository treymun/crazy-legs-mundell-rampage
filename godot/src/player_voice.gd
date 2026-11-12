## What a player other than the local one sounds like on this machine. While
## that player acts (Game.focus) the game's `sound` is this: a sound the code
## plays "at the player" (their gun, a pickup, a grunt) is placed where they
## stand for the local player's ears; what only the local player's own
## machine does with sound (the fuse hiss, the room's reverb, the music, the
## radio, stings) does nothing. Presentation only: never changes play.
class_name PlayerVoice
extends RefCounted

var game
var who: Player
var effects_gain := 1.0
var footstep_gain := 1.0
var voice_gain := .8
var music_gain := .5
var ambient_gain := 1.0
var radio_gain := 0.0


func _init(p_game, p_who: Player) -> void:
	game = p_game
	who = p_who


func has(cue: String) -> bool:
	return game.speaker.has(cue)


func play(name: String, volume := 1.0, _pan := 0.0, _cutoff := Sound.OPEN_CUTOFF) -> void:
	var place: Vector2 = game.sound_position(who.x, who.y, volume)
	game.speaker.play(name, place.x, place.y, game.sound_cutoff(who.x, who.y))


func play_voice(name: String, volume: float, _pan: float) -> float:
	var place: Vector2 = game.sound_position(who.x, who.y, volume)
	return game.speaker.play_voice(name, place.x, place.y)


func sting(_cue: String) -> void:
	pass


func set_fuse(_burning: bool) -> void:
	pass


func set_tool(_active: bool) -> void:
	pass


func stop_voice() -> void:
	pass


func set_room(_room_name) -> void:
	pass


func set_space(_kind: String) -> void:
	pass


func set_radio(_playing: bool, _volume := 0.0, _pan := 0.0) -> void:
	pass


func set_bed(_slot: int, _cue: String, _volume: float, _pan := 0.0, _cutoff := 0.0) -> void:
	pass


func set_fight(_active: bool) -> void:
	pass


func level_music(_gain: float) -> void:
	pass


func pause_world() -> void:
	pass
