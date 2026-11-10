## Port of audio.py's Sound manager and score_player.py's music stream player.
##
## pygame handed the reference one channel per role. Here every role is an
## AudioStreamPlayer on its own mixer bus, and that bus carries an
## AudioEffectPanner. Setting the player's linear volume to (left+right)/2 and
## the panner to (right-left)/(left+right) reproduces pygame's
## Channel.set_volume(left, right) balance law exactly:
##     L = v*(1-pan), R = v*(1+pan)
class_name Sound
extends Node

const SCORES := {
	"music": ["music", "county_line", "porchlight_stomp"],
	"fair_score": ["fair_score", "tickets_after_dark", "closing_time_shuffle"],
	"mill_score": ["mill_score", "green_chain", "apron_run"],
	"quarry_score": ["quarry_score", "copper_and_steam", "last_load"],
}

const PRIORITY := [
	"revolver",
	"shotgun",
	"shotgun_both",
	"rifle",
	"armgun",
	"explosion",
	"hurt",
	"player_down",
	"glass_break",
	"match_strike",
	"pressure_gun",
	"riveter_pair",
	"bottle_launcher",
	"rocket_pop"
]

const WARNS := [
	"boiler_priming",
	"chalk_cough",
	"rudy_warn",
	"foreman_warn",
	"baron_warn",
	"sheriff_siren",
	"whistle",
	"barker_wind",
	"millhand_rev",
	"lantern_charge",
	"deputy_work",
	"tosser_rattle",
	"chain_raise",
	"rat_hiss",
	"saucer_charge",
	"guard_charge",
	"skeeter_dive",
	"enemy_pump",
	"coot_cock",
	"clone_bolt",
	"pressure_vent"
]

const REPORT_GAIN := {
	"revolver": .84,
	"shotgun": .82,
	"shotgun_both": .64,
	"rifle": .83,
	"explosion": .82,
	"rocket_pop": .88,
	"riveter_pair": .88,
	"bottle_launcher": .94,
	"crowbar": .77,
	"slingblade": .72,
	"sling_hit": .70,
	"ripsaw": .62,
	"saw_bounce": .56,
	"saw_hit": .58,
	"armgun": .79,
	# Keep the report and warning cues clear when a blast downs an actor.
	"actor_cloth_down": .75,
	"actor_shell_down": .75,
	"actor_tool_down": .75,
}

const VARIANTS := {
	"rifle": ["rifle", "rifle_alt", "rifle_alt2"],
	"revolver": ["revolver", "revolver_alt"],
	"hurt": ["hurt", "hurt_alt", "hurt_alt2"],
	"yee_haw": ["yee_haw", "yee_haw_alt"],
}

const TOOL_GAIN := .26
const STEP_GAIN := .83
const AMB_FADE := .33
const EFFECT_VOICES := 14


## Small deterministic generator so shuffling never touches the global RNG.
class ShuffleRng:
	extends RefCounted
	var state := 0

	func _init(seed_value := 1997) -> void:
		state = ((seed_value + 1) * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF

	func next() -> float:
		state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
		return float(state >> 10) / 9007199254740992.0


## score_player.ShuffleBank: one shuffled bag per chapter, no immediate repeat.
class ShuffleBank:
	extends RefCounted
	var tracks: Array = []
	var rng = null
	var bag: Array = []
	var track = null
	var offset := 0.0

	func _init(p_tracks: Array, p_rng) -> void:
		tracks = p_tracks.duplicate()
		rng = p_rng

	func advance() -> void:
		if bag.is_empty():
			bag = tracks.duplicate()
			var i := bag.size() - 1
			while i > 0:
				var j := int(rng.next() * float(i + 1))
				var swap = bag[i]
				bag[i] = bag[j]
				bag[j] = swap
				i -= 1
			if not bag.is_empty() and bag[bag.size() - 1] == track:
				var last := bag.size() - 1
				var swap2 = bag[last]
				bag[last] = bag[0]
				bag[0] = swap2
		track = bag.pop_back()
		offset = 0.0


## score_player.ScorePlayer: single music stream, shuffled banks, fades, seeks.
class ScorePlayer:
	extends RefCounted
	const FADE := .24
	const CODA_FADE := .12

	var assets: Assets
	var player: AudioStreamPlayer
	var banks := {}
	var requested := "title"
	var active = null
	var track = null
	var offset := 0.0
	var finish := 0.0
	var last_position := 0.0
	var gain := 0.0
	var master := .5
	var enabled := false
	var paused := false
	var reopen := false
	var ready := false

	func _init(
		p_assets: Assets, p_player: AudioStreamPlayer, definitions: Dictionary, seed_value := 1997
	) -> void:
		assets = p_assets
		player = p_player
		var rng := ShuffleRng.new(seed_value)
		for key in definitions:
			banks[key] = ShuffleBank.new(definitions[key], rng)

	## Absolute position in the current stream, in seconds.
	func position() -> float:
		if player.playing:
			var pos := player.get_playback_position()
			# Godot reports the stream playhead; be tolerant if a build reports
			# it relative to the play() call instead.
			if pos + 1.0 < offset:
				pos += offset
			last_position = pos
		return last_position

	func play_end(track_name: String) -> float:
		var length := assets.track_length(track_name)
		if length <= 0.0:
			return 0.0
		return minf(length, float(assets.music_ends.get(track_name, length)))

	func request(context: String) -> void:
		requested = context
		if active == null and enabled and not paused:
			start(context)

	func level(value: float) -> void:
		master = value
		player.volume_linear = master * gain

	func set_enabled(value: bool) -> void:
		enabled = value
		sync_pause()

	func pause(value: bool) -> void:
		if paused != value:
			paused = value
			sync_pause()

	func sync_pause() -> void:
		if not ready:
			return
		if not enabled or paused:
			position()
			player.stream_paused = true
		elif active == null:
			start(requested)
		else:
			player.stream_paused = false

	func start(context: String, store := true) -> void:
		if not ready:
			return
		if store and banks.has(active):
			var previous: ShuffleBank = banks[active]
			if player.playing and not player.stream_paused:
				previous.offset = position()
			else:
				previous.advance()
		var track_name := ""
		var start_at := 0.0
		var loop := false
		if banks.has(context):
			var bank: ShuffleBank = banks[context]
			if bank.track == null:
				bank.advance()
			if bank.offset > play_end(String(bank.track)) - .48:
				bank.advance()
			track_name = String(bank.track)
			start_at = bank.offset
		else:
			track_name = context
			loop = context != "victory"
		var stream: AudioStream = null
		if track_name == "title" or track_name == "victory":
			stream = assets.jingle(track_name)
		else:
			stream = assets.track(track_name)
		if stream == null:
			active = context
			return
		Assets.set_loop(stream, loop)
		player.stream_paused = false
		player.stream = stream
		active = context
		track = track_name
		offset = start_at
		finish = play_end(track_name) if banks.has(context) else 0.0
		last_position = start_at
		gain = 0.0
		reopen = false
		player.volume_linear = 0.0
		if start_at >= .05:
			player.play(start_at)
		else:
			player.play()

	func update(dt: float) -> void:
		if not enabled or paused:
			return
		var bank: ShuffleBank = banks.get(active)
		var remaining := (finish - position()) if bank != null else 0.0
		var switching: bool = active != requested or reopen
		if switching:
			gain = maxf(0.0, gain - dt / FADE)
			if gain == 0.0 or not player.playing:
				start(requested, not reopen)
		elif bank != null and (remaining <= 0.0 or not player.playing):
			bank.advance()
			start(active, false)
		else:
			var cap := 1.0 if bank == null else maxf(0.0, minf(1.0, remaining / CODA_FADE))
			gain = minf(cap, gain + dt / FADE)
		player.volume_linear = master * gain

	func bookmark(context: String):
		var bank: ShuffleBank = banks.get(context)
		if bank == null or bank.track == null:
			return null
		var at := bank.offset
		if active == context and not reopen:
			at = position()
		return {"track": bank.track, "remaining": bank.bag.duplicate(), "offset": at}

	func restore(context: String, value) -> void:
		if value == null or not banks.has(context):
			return
		var bank: ShuffleBank = banks[context]
		bank.track = value["track"]
		bank.offset = float(value["offset"])
		bank.bag = (value["remaining"] as Array).duplicate()
		reopen = reopen or active == context


## One mixer voice: a player plus the bus carrying its panner.
class Voice:
	extends RefCounted
	var player: AudioStreamPlayer
	var bus := 0
	var cue := ""

	func _init(p_player: AudioStreamPlayer, p_bus: int) -> void:
		player = p_player
		bus = p_bus


var assets: Assets

var music := true
var score := "title"
var variations := {}
var room = null
var room_slot := 0
var radio_gain := 0.0
var effects_gain := 1.0
var footstep_gain := 1.0
var voice_gain := .8
var music_gain := .50
var ambient_gain := 1.0
var mix_headroom := 1.0
var pan_width := .70

var score_player: ScorePlayer

var _effects: Array[Voice] = []
var _ambience: Array[Voice] = []
var _radio: Voice
var _priority: Voice
var _fuse: Voice
var _warning: Voice
var _warning_alt: Voice
var _sting: Voice
var _tool: Voice
var _voice: Voice
var _music: AudioStreamPlayer

var _amb_target := [0.0, 0.0]
var _amb_rate := [0.0, 0.0]


func _init(p_art: Assets) -> void:
	assets = p_art
	var slot := 0
	for _i in EFFECT_VOICES:
		_effects.append(_make_voice(slot))
		slot += 1
	for i in 2:
		_ambience.append(_make_voice(slot))
		slot += 1
	_radio = _make_voice(slot)
	slot += 1
	_priority = _make_voice(slot)
	slot += 1
	_fuse = _make_voice(slot)
	slot += 1
	_warning = _make_voice(slot)
	slot += 1
	_warning_alt = _make_voice(slot)
	slot += 1
	_sting = _make_voice(slot)
	slot += 1
	_tool = _make_voice(slot)
	slot += 1
	_voice = _make_voice(slot)

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)
	_music.bus = "Master"
	# Unseeded in the reference: a different track order on every launch.
	score_player = ScorePlayer.new(
		assets,
		_music,
		SCORES,
		int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	)
	set_levels(1.0, 1.0, 1.0, 2)


func _ready() -> void:
	score_player.ready = true
	score_player.set_enabled(music)


func _make_voice(slot: int) -> Voice:
	var player := AudioStreamPlayer.new()
	player.name = "Voice%d" % slot
	player.max_polyphony = 1
	var bus := _ensure_bus(slot)
	player.bus = AudioServer.get_bus_name(bus)
	add_child(player)
	return Voice.new(player, bus)


## Every voice gets its own bus because the panner is a bus effect.
func _ensure_bus(slot: int) -> int:
	var bus_name := "pan_%d" % slot
	for i in range(1, AudioServer.get_bus_count()):
		if AudioServer.get_bus_name(i) == bus_name:
			return i
	var index := AudioServer.get_bus_count()
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	var panner := AudioEffectPanner.new()
	panner.pan = 0.0
	AudioServer.add_bus_effect(index, panner)
	return index


func _all_voices() -> Array:
	var out: Array = _effects.duplicate()
	out.append_array(_ambience)
	out.append(_radio)
	out.append(_priority)
	out.append(_fuse)
	out.append(_warning)
	out.append(_warning_alt)
	out.append(_sting)
	out.append(_tool)
	out.append(_voice)
	return out


## pygame Channel.set_volume(left, right) expressed as volume + pan.
func _balance(v: Voice, left: float, right: float) -> void:
	var total := left + right
	if total <= .00001:
		v.player.volume_linear = 0.0
		return
	v.player.volume_linear = total * .5
	var panner := AudioServer.get_bus_effect(v.bus, 0) as AudioEffectPanner
	if panner != null:
		panner.pan = clampf((right - left) / total, -1.0, 1.0)


func _start(v: Voice, name: String, cue: String, volume: float, pan: float) -> void:
	var stream := assets.cue(cue)
	if stream == null:
		return
	v.cue = cue
	v.player.stream = stream
	v.player.play()
	var scale := 1.0
	if name.begins_with("distant_"):
		scale = ambient_gain
	elif name.begins_with("step_"):
		scale = footstep_gain * STEP_GAIN
	elif name.begins_with("room_"):
		scale = .72
	else:
		scale = float(REPORT_GAIN.get(name, 1.0))
	var gain := minf(1.0, effects_gain * volume * scale) * .82 * mix_headroom
	_balance(
		v, gain * (1.0 - maxf(0.0, pan) * pan_width), gain * (1.0 + minf(0.0, pan) * pan_width)
	)


func _free_effect():
	for v: Voice in _effects:
		if not v.player.playing:
			return v
	return null


func _playing_count(cue: String) -> int:
	var count := 0
	for v: Voice in _all_voices():
		if v.player.playing and v.cue == cue:
			count += 1
	return count


func has(cue: String) -> bool:
	return assets.has_cue(cue)


func play(name: String, volume := 1.0, pan := 0.0) -> void:
	if effects_gain == 0.0:
		return
	var cue := name
	var variant: Array = VARIANTS.get(name, [])
	if not variant.is_empty():
		var index := int(variations.get(name, 0))
		cue = String(variant[index % variant.size()])
		if not assets.has_cue(cue):
			cue = name
		variations[name] = index + 1
	if not assets.has_cue(cue):
		return
	var target = null
	if WARNS.has(name):
		if _playing_count(cue) > 0:
			return
		if not _warning.player.playing:
			target = _warning
		elif not _warning_alt.player.playing:
			target = _warning_alt
		if target == null:
			target = _free_effect()
	else:
		target = _free_effect()
	if target == null and PRIORITY.has(name):
		target = _priority
	if target == null:
		return
	_start(target, name, cue, volume, pan)


func set_room(room_name) -> void:
	var target = (
		null if room_name == null or String(room_name) == "" else "amb_" + String(room_name)
	)
	if target == room:
		return
	room = target
	var old := room_slot
	_amb_target[old] = 0.0
	_amb_rate[old] = maxf(_ambience[old].player.volume_linear, .0001) / AMB_FADE
	room_slot ^= 1
	if target == null:
		return
	if not assets.has_cue(target):
		return
	var stream := assets.cue(target)
	if stream == null:
		return
	Assets.set_loop(stream, true)
	var v := _ambience[room_slot]
	v.cue = target
	v.player.stream = stream
	v.player.volume_linear = 0.0
	v.player.play()
	_amb_target[room_slot] = .78 * ambient_gain * mix_headroom
	_amb_rate[room_slot] = _amb_target[room_slot] / AMB_FADE


func _process(delta: float) -> void:
	for i in 2:
		if _amb_rate[i] <= 0.0:
			continue
		var player: AudioStreamPlayer = _ambience[i].player
		var step: float = _amb_rate[i] * delta
		var target: float = _amb_target[i]
		if target <= 0.0:
			var next := maxf(0.0, player.volume_linear - step)
			if next <= .0001:
				player.stop()
				player.volume_linear = 0.0
				_amb_rate[i] = 0.0
			else:
				player.volume_linear = next
		else:
			player.volume_linear = minf(target, player.volume_linear + step)
			if player.volume_linear >= target:
				_amb_rate[i] = 0.0


func set_radio(playing: bool, volume := 0.0, pan := 0.0) -> void:
	var stream := assets.cue("jukebox")
	if playing and stream != null:
		if not _radio.player.playing:
			Assets.set_loop(stream, true)
			_radio.cue = "jukebox"
			_radio.player.stream = stream
			_radio.player.play()
		var gain := effects_gain * volume * mix_headroom
		_balance(
			_radio,
			gain * (1.0 - maxf(0.0, pan) * pan_width),
			gain * (1.0 + minf(0.0, pan) * pan_width)
		)
	elif _radio.player.playing:
		_radio.player.stop()
	var target := minf(.80, volume * 1.28) if playing else 0.0
	if absf(radio_gain - target) >= .018 or (not playing and radio_gain > 0.0):
		radio_gain = target
		score_player.level(music_gain * (1.0 - target))


func set_levels(effects: float, music_level: float, ambience := 1.0, stereo := 2) -> void:
	# Reserve peak room when loud music and combat play together.
	# Keep the stock mix and the balance between warnings and reports.
	mix_headroom = 1.0 - .14 * effects * maxf(0.0, 2.0 * music_level - 1.0)
	effects_gain = effects
	music_gain = music_level * .86 * mix_headroom
	ambient_gain = ambience
	pan_width = [0.0, .35, .70, .93][clampi(stereo, 0, 3)]
	if score_player != null:
		score_player.level(music_gain * (1.0 - radio_gain))
	_amb_target[room_slot] = .78 * ambience * mix_headroom
	if _amb_rate[room_slot] <= 0.0:
		_ambience[room_slot].player.volume_linear = _amb_target[room_slot]
	if _fuse.player.playing:
		_fuse.player.volume_linear = .64 * effects * mix_headroom
	if _tool.player.playing:
		_tool.player.volume_linear = TOOL_GAIN * effects * mix_headroom
	if _sting.player.playing:
		_sting.player.volume_linear = .84 * music_gain


func set_fuse(burning: bool) -> void:
	if burning:
		if not _fuse.player.playing:
			var stream := assets.cue("fuse_hiss")
			if stream == null:
				return
			Assets.set_loop(stream, true)
			_fuse.cue = "fuse_hiss"
			_fuse.player.stream = stream
			_fuse.player.play()
			_fuse.player.volume_linear = .64 * effects_gain * mix_headroom
	elif _fuse.player.playing:
		_fuse.player.stop()


func set_tool(active: bool) -> void:
	if active:
		if not _tool.player.playing:
			var stream := assets.cue("saw_motor")
			if stream == null:
				return
			Assets.set_loop(stream, true)
			_tool.cue = "saw_motor"
			_tool.player.stream = stream
			_tool.player.play()
			_tool.player.volume_linear = TOOL_GAIN * effects_gain * mix_headroom
	elif _tool.player.playing:
		_tool.player.stop()


func play_voice(name: String, volume: float, pan: float) -> float:
	var stream := assets.cue(name)
	if stream == null:
		return 1.55
	if voice_gain != 0.0 and not (_voice.player.playing and _voice.cue == name):
		var gain := volume * voice_gain * .88 * mix_headroom
		_voice.cue = name
		_voice.player.stream = stream
		_voice.player.play()
		_balance(
			_voice,
			gain * (1.0 - maxf(0.0, pan) * pan_width),
			gain * (1.0 + minf(0.0, pan) * pan_width)
		)
	return stream.get_length()


func stop_voice() -> void:
	if _voice.player.playing:
		_voice.player.stop()


func pause_world() -> void:
	set_room(null)
	set_radio(false)
	set_fuse(false)
	set_tool(false)
	stop_voice()
	for v: Voice in _all_voices():
		if v.player.playing and WARNS.has(v.cue):
			v.player.stop()
	if _priority.player.playing:
		_priority.player.stop()


func set_score(cue: String) -> void:
	if cue != score and _sting.player.playing:
		_sting.player.stop()
	score = cue
	if score_player != null:
		score_player.request(cue)


func pause_score(paused: bool) -> void:
	if score_player == null:
		return
	score_player.pause(paused)
	if _sting.player.playing:
		_sting.player.stream_paused = paused


func tick_score(dt: float) -> void:
	if score_player != null:
		score_player.update(dt)


func bookmark_score(context: String):
	return score_player.bookmark(context) if score_player != null else null


func restore_score(context: String, value) -> void:
	if score_player != null:
		score_player.restore(context, value)


## The score master level (game.gd drives it for ducking).
func level_music(gain: float) -> void:
	if score_player != null:
		score_player.level(gain)


func sting(cue: String) -> void:
	var stream := assets.cue(cue)
	if music and stream != null:
		_sting.cue = cue
		_sting.player.stream = stream
		_sting.player.play()
		_sting.player.volume_linear = .84 * music_gain


func toggle_music() -> void:
	if score_player != null:
		music = not music
		score_player.set_enabled(music)
		if not music and _sting.player.playing:
			_sting.player.stop()
