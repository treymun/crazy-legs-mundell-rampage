## The sound an online client's copy hears through while its own hands step
## plays a moment this machine already showed (net_shot_predict.gd): every
## play() is written down instead of heard, and the watcher plays afterwards
## only what was not heard already (a confirmed shot's bang is dropped, a
## kill's tick or an enemy's yelp is played). Everything else goes straight
## through to the real sound.
class_name NetEchoSound
extends GameSound

## The sound behind it (the game's speaker).
var real: GameSound = null
## [name, volume, pan, cutoff, rate] for each play held.
var held: Array = []


func current_score() -> String:
	return real.score


func current_music_gain() -> float:
	return real.music_gain


func current_voice_gain() -> float:
	return real.voice_gain


func current_lift() -> float:
	return real.score_lift


func set_lift(value: float) -> void:
	real.score_lift = value


func node() -> Sound:
	return real.node()


func has(cue: String) -> bool:
	return real.has(cue)


func play(name: String, volume := 1.0, pan := 0.0, cutoff := Sound.OPEN_CUTOFF) -> void:
	held.append([name, volume, pan, cutoff, 1.0])


func play_at_rate(
	name: String, volume := 1.0, pan := 0.0, cutoff := Sound.OPEN_CUTOFF, rate := 1.0
) -> void:
	held.append([name, volume, pan, cutoff, rate])


## Plays one held entry on the real sound.
func let_out(entry: Array) -> void:
	var name: String = entry[0]
	var volume: float = entry[1]
	var pan: float = entry[2]
	var cutoff: float = entry[3]
	var rate: float = entry[4]
	if rate == 1.0:
		real.play(name, volume, pan, cutoff)
	else:
		real.play_at_rate(name, volume, pan, cutoff, rate)


func play_voice(name: String, volume := 1.0, pan := 0.0) -> float:
	return real.play_voice(name, volume, pan)


func sting(cue: String) -> void:
	real.sting(cue)


func set_score(cue: String) -> void:
	real.set_score(cue)


func pause_score(paused: bool) -> void:
	real.pause_score(paused)


func set_fuse(burning: bool) -> void:
	real.set_fuse(burning)


func set_tool(active: bool) -> void:
	real.set_tool(active)


func stop_voice() -> void:
	real.stop_voice()


func set_room(room_name: Variant) -> void:
	real.set_room(room_name)


func set_space(kind: String) -> void:
	real.set_space(kind)


func set_radio(playing: bool, volume := 0.0, pan := 0.0) -> void:
	real.set_radio(playing, volume, pan)


func set_bed(
	slot: int, cue: String, volume: float, pan := 0.0, cutoff := Sound.OPEN_CUTOFF
) -> void:
	real.set_bed(slot, cue, volume, pan, cutoff)


func set_fight(active: bool) -> void:
	real.set_fight(active)


func level_music(gain: float) -> void:
	real.level_music(gain)


func pause_world() -> void:
	real.pause_world()
