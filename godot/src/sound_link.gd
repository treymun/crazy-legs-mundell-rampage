## This machine's Sound as the game's GameSound: every call goes straight
## through to the Sound node (Game._init wraps the Sound it is given).
class_name SoundLink
extends GameSound

var sound: Sound


func _init(p_sound: Sound) -> void:
	sound = p_sound


func current_score() -> String:
	return sound.score


func current_music_gain() -> float:
	return sound.music_gain


func current_voice_gain() -> float:
	return sound.voice_gain


func current_lift() -> float:
	return sound.score_lift


func set_lift(value: float) -> void:
	sound.score_lift = value


func node() -> Sound:
	return sound


func has(cue: String) -> bool:
	return sound.has(cue)


func play(name: String, volume := 1.0, pan := 0.0, cutoff := Sound.OPEN_CUTOFF) -> void:
	sound.play(name, volume, pan, cutoff)


func play_at_rate(
	name: String, volume := 1.0, pan := 0.0, cutoff := Sound.OPEN_CUTOFF, rate := 1.0
) -> void:
	sound.play_at_rate(name, volume, pan, cutoff, rate)


func play_voice(name: String, volume := 1.0, pan := 0.0) -> float:
	return sound.play_voice(name, volume, pan)


func sting(cue: String) -> void:
	sound.sting(cue)


func set_score(cue: String) -> void:
	sound.set_score(cue)


func pause_score(paused: bool) -> void:
	sound.pause_score(paused)


func set_fuse(burning: bool) -> void:
	sound.set_fuse(burning)


func set_tool(active: bool) -> void:
	sound.set_tool(active)


func stop_voice() -> void:
	sound.stop_voice()


func set_room(room_name: Variant) -> void:
	sound.set_room(room_name)


func set_space(kind: String) -> void:
	sound.set_space(kind)


func set_radio(playing: bool, volume := 0.0, pan := 0.0) -> void:
	sound.set_radio(playing, volume, pan)


func set_bed(
	slot: int, cue: String, volume: float, pan := 0.0, cutoff := Sound.OPEN_CUTOFF
) -> void:
	sound.set_bed(slot, cue, volume, pan, cutoff)


func set_fight(active: bool) -> void:
	sound.set_fight(active)


func level_music(gain: float) -> void:
	sound.level_music(gain)


func pause_world() -> void:
	sound.pause_world()
