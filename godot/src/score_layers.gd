## The fight music in four levels (pass 15). Until then a chapter's music was
## its track or its fight loop, and with a fight every 8 to 12 s the loop
## played 80 to 97 % of every chapter. Now (features/fight_music.gd decides
## the level; sound.gd's ScorePlayer crossfades the track and the fight
## player as before):
##
##   CALM   the chapter's track;
##   BUILD  a hand awake, the fight not on the player yet: the track gives
##          way to the fight loop's own drums alone (pulse_<chapter>);
##   FIGHT  the whole fight loop;
##   PEAK   a director's peak or a RAMPAGE: the loop with its top riff laid
##          over it (peak_<chapter>), about 2 LU louder.
##
## The layers are made free from each loop (scripts/audio_layers.py), as long
## as it to the sample, and the fight player plays the three as one
## AudioStreamSynchronized: each layer's gain moves under the one stream, so
## going from BUILD to FIGHT to PEAK never shifts a beat. A chapter without
## its layers (a browser build still fetching them) plays its loop alone, and
## its BUILD stays on the track. Looks only: nothing here touches play.
class_name ScoreLayers
extends RefCounted

const CALM := 0
const BUILD := 1
const FIGHT := 2
const PEAK := 3
const NAMES: Array[String] = ["CALM", "BUILD", "FIGHT", "PEAK"]

## The streams under the fight player, in order: the loop, its drums, its riff.
const LOOP := 0
const PULSE := 1
const RIFF := 2
## Each layer's gain wanted at each level (CALM keeps what was playing: the
## fight player is fading out under the track then).
const WANT := [[], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0], [1.0, 0.0, 1.0]]
## Seconds a layer takes to come in and to go (the loop comes in over the
## drums quicker than they leave, so the beat never dips).
const RISE: Array[float] = [.6, 1.0, .5]
const FALL: Array[float] = [2.5, 1.2, 2.0]
## The quietest a layer is set (dB): out.
const OUT_DB := -60.0

## The stream made for each fight loop (by its name), and each layer's gain
## now (0..1), the same for whichever is playing.
static var _made := {}
static var gains: Array[float] = [1.0, 0.0, 0.0]


## The stream the fight player plays for `fight_track`: its loop and its two
## layers as one, or the loop alone when the layers are not to be had.
static func stream_of(assets: Assets, fight_track: String) -> AudioStream:
	var loop := assets.track(fight_track)
	if loop == null or not layered(assets, fight_track):
		return loop
	var made: AudioStreamSynchronized = _made.get(fight_track)
	if made == null:
		var stem := fight_track.trim_prefix("fight_")
		made = AudioStreamSynchronized.new()
		made.stream_count = 3
		var parts: Array[AudioStreamOggVorbis] = [
			loop, assets.track("pulse_" + stem), assets.track("peak_" + stem)
		]
		for i in parts.size():
			Assets.set_loop(parts[i], true)
			made.set_sync_stream(i, parts[i])
		_made[fight_track] = made
		_apply(made)
	return made


## Whether `fight_track`'s layers are in the packs.
static func layered(assets: Assets, fight_track: String) -> bool:
	if assets == null or fight_track == "":
		return false
	var stem := fight_track.trim_prefix("fight_")
	return assets.music_index.has("pulse_" + stem) and assets.music_index.has("peak_" + stem)


## Every tick: each layer's gain toward what `level` wants; at once while the
## fight player is silent (`mix` 0), so it starts at the level it is asked for.
static func step(dt: float, level: int, mix: float) -> void:
	var want: Array = WANT[clampi(level, CALM, PEAK)]
	if want.is_empty():
		return
	var moved := false
	for i in 3:
		var aim: float = want[i]
		var now := gains[i]
		var next := (
			aim if mix <= 0.0 else move_toward(now, aim, dt / (RISE[i] if aim > now else FALL[i]))
		)
		if next != now:
			gains[i] = next
			moved = true
	if moved:
		for made: AudioStreamSynchronized in _made.values():
			_apply(made)


static func _apply(made: AudioStreamSynchronized) -> void:
	for i in 3:
		made.set_sync_stream_volume(i, maxf(OUT_DB, linear_to_db(maxf(gains[i], 1e-4))))
