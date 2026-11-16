## What play asks of the game's sound (Game.sound, Game.speaker): one typed
## interface for the three things that answer it. SoundLink is this
## machine's Sound (a Node, so it is wrapped); PlayerVoice places another
## player's sounds where they stand; QuietSound is a host's, which plays
## nothing. Each method here does nothing; they override what they play.
class_name GameSound
extends RefCounted

## The music playing now ("" none).
var score: String:
	get:
		return current_score()
	set(value):
		_score = value

var _score := ""
## The music's and voices' levels (settings), and the boss loop's lift.
var music_gain: float:
	get:
		return current_music_gain()
var voice_gain: float:
	get:
		return current_voice_gain()
var score_lift: float:
	get:
		return current_lift()
	set(value):
		set_lift(value)

var _music := 0.0
var _voice := 0.0
var _lift := 1.0


func current_score() -> String:
	return _score


func current_music_gain() -> float:
	return _music


func current_voice_gain() -> float:
	return _voice


func current_lift() -> float:
	return _lift


func set_lift(value: float) -> void:
	_lift = value


## This machine's Sound behind it (null for a voice or a host).
func node() -> Sound:
	return null


func has(_cue: String) -> bool:
	return false


func play(_name: String, _volume := 1.0, _pan := 0.0, _cutoff := Sound.OPEN_CUTOFF) -> void:
	pass


## play() at `rate` times its pitch (a vehicle's engine rising with its
## speed); where nothing can change the pitch it plays as it is.
func play_at_rate(
	name: String, volume := 1.0, pan := 0.0, cutoff := Sound.OPEN_CUTOFF, _rate := 1.0
) -> void:
	play(name, volume, pan, cutoff)


func play_voice(_name: String, _volume := 1.0, _pan := 0.0) -> float:
	return 0.0


## Whether a spoken line (Sound.SPEECH) is still playing: the voices wait or
## stay quiet rather than talk over each other.
func talking() -> bool:
	return false


## Stops the spoken lines playing as effects (a boss's line cuts in).
func hush_speech() -> void:
	pass


func sting(_cue: String) -> void:
	pass


func set_score(_cue: String) -> void:
	pass


func pause_score(_paused: bool) -> void:
	pass


func set_fuse(_burning: bool) -> void:
	pass


func set_tool(_active: bool) -> void:
	pass


func stop_voice() -> void:
	pass


func set_room(_room_name: Variant) -> void:
	pass


func set_space(_kind: String) -> void:
	pass


func set_radio(_playing: bool, _volume := 0.0, _pan := 0.0) -> void:
	pass


func set_bed(
	_slot: int, _cue: String, _volume: float, _pan := 0.0, _cutoff := Sound.OPEN_CUTOFF
) -> void:
	pass


func set_fight(_active: bool) -> void:
	pass


func level_music(_gain: float) -> void:
	pass


func pause_world() -> void:
	pass
