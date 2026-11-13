## The sound of an authoritative host's game (game_host.gd): every call the
## game, its enemies and its features make on game.sound or game.speaker is
## answered and does nothing. Nobody listens to a host.
class_name QuietSound
extends RefCounted

var effects_gain := 0.0
var footstep_gain := 0.0
var voice_gain := 0.0
var music_gain := 0.0
var ambient_gain := 0.0
var radio_gain := 0.0
var score := ""
var score_lift := 1.0
var reverb_on := false


func has(_cue: String) -> bool:
	return false


func play(_name: String, _volume := 1.0, _pan := 0.0, _cutoff := 0.0) -> void:
	pass


func play_voice(_name: String, _volume := 1.0, _pan := 0.0) -> float:
	return 0.0


func sting(_cue: String) -> void:
	pass


func set_score(name: String) -> void:
	score = name


func pause_score(_paused: bool) -> void:
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
