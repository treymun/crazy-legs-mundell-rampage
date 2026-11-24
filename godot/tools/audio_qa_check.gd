## The sound's wiring and finish, headless (check_all, quick; pass 9):
##
##   Godot --headless --path <project> --script res://tools/audio_qa_check.gd
##
## - Every cue the game names in a literal (play, play_at_rate, sound_at,
##   sting, play_voice, set_bed) is in the bank or made in code
##   (Assets.MADE_CUES): pass 9 found "honk", "impact_stone" and "step_water"
##   named and never made, so those moments were silent.
## - Every cue in the bank starts and ends at silence (no click) unless it
##   loops, and every loop's end runs into its start.
## - Every CLEAN copy is as loud as its cussing take (the duck call used to
##   set the whole line's level, up to 8 LU under).
## - The music's holds stack: play's own (a blast, a caption) with Dub talking
##   over the song and a jukebox playing (level_music used to undo both).
## - A hand never says the same line twice running (enemy_barks _fresh).
##
## The full measurement (loudness against each family, true peak, loop joins,
## same takes, cues nobody names) is scripts/audio_qa.py --check, run by
## check_all's lint and CI's lint job. Nobody listens here.
extends SceneTree

## Cues the game loops (Sound: the beds, the tools, the jukebox, the rooms).
const LOOPS := [
	"jukebox",
	"fuse_hiss",
	"saw_motor",
	"rain_loop",
	"rain_roof",
	"fire_crackle",
	"ember_crackle",
	"still_bubble",
	"generator_hum",
	"airboat_wake",
	"tornado_roar",
	"hog_stampede",
	"core_thrum",
	# The flight loops and the saucers' hum (src/mover_sounds.gd, doppler.cfg).
	"fly_rocket",
	"fly_whoosh",
	"fly_bowl",
	"saucer_hum",
]
const CALL := (
	"\\.(?:play|play_at_rate|sting|play_voice|set_bed|sound_at)\\(\\s*"
	+ '(?:[A-Za-z_.0-9]+\\s*,\\s*)?"([a-z][a-z0-9_\\-]*)"'
)
## A first or last sample past this (of full scale) is a click.
const EDGE := .02
## A CLEAN copy's level against its cussing take's, dB.
const CLEAN_DB := 2.0

## Where audio_build.py writes the finished cues.
var final_dir := (
	ProjectSettings.globalize_path("res://").path_join("../audio_src/final/sfx").simplify_path()
)
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("\nAUDIO QA (WIRING, EDGES, LOOPS, CLEAN, MUSIC HOLDS, BARKS)")
	_wiring(main)
	_edges(main)
	_clean(main)
	_music(main)
	_barks(main)
	print("")
	print("AUDIO QA OK" if failures.is_empty() else "%d AUDIO QA CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _sources(folder: String, out: Array) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(folder.path_join(name))
	for sub in dir.get_directories():
		_sources(folder.path_join(sub), out)


func _wiring(main) -> void:
	var assets: Assets = main.sound.assets
	var files: Array = []
	_sources("res://src", files)
	var rx := RegEx.create_from_string(CALL)
	var named := {}
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for m in rx.search_all(text):
			var cue := m.get_string(1)
			if not cue.ends_with("_"):
				named[cue] = path.get_file()
	var missing: Array = []
	for cue: String in named:
		if not assets.has_cue(cue) and not Assets.MADE_CUES.has(cue):
			missing.append("%s (%s)" % [cue, named[cue]])
	_check(
		named.size() > 150 and missing.is_empty(),
		(
			"every cue the game names in a literal is made (%d named; missing: %s)"
			% [named.size(), ", ".join(missing)]
		)
	)
	for cue in ["honk", "impact_stone", "church_bell", "cruiser_siren"]:
		_check(assets.has_cue(cue), "%s is in the bank" % cue)


## The finished 16-bit samples of `cue` (audio_src/final/sfx, what the bank
## is packed from: the bank itself holds QOA), or an empty array.
func _pcm(cue: String) -> PackedByteArray:
	var path := final_dir.path_join(cue + ".wav")
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var raw := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 <= raw.size():
		var size := raw.decode_u32(at + 4)
		if raw.slice(at, at + 4).get_string_from_ascii() == "data":
			return raw.slice(at + 8, at + 8 + size)
		at += 8 + size + (size & 1)
	return PackedByteArray()


func _edges(main) -> void:
	var assets: Assets = main.sound.assets
	var clicks: Array = []
	var seams: Array = []
	var looked := 0
	if not DirAccess.dir_exists_absolute(final_dir):
		_check(true, "(no audio_src/final/sfx beside the project: edges not measured)")
		return
	for cue: String in assets.sfx_index:
		if Assets.MADE_CUES.has(cue):
			continue
		var data := _pcm(cue)
		if data.size() < 64:
			continue
		looked += 1
		var first := absf(data.decode_s16(0) / 32768.0)
		var last := absf(data.decode_s16(data.size() - 2) / 32768.0)
		if cue.begins_with("amb_") or LOOPS.has(cue):
			# The step across the join, against the largest step inside.
			var jump := absi(data.decode_s16(0) - data.decode_s16(data.size() - 2))
			var inside := 0
			for i in range(0, data.size() - 3, 2):
				inside = maxi(inside, absi(data.decode_s16(i + 2) - data.decode_s16(i)))
			if jump > inside:
				seams.append("%s %d over %d" % [cue, jump, inside])
		elif first > EDGE or last > EDGE:
			clicks.append("%s %.3f/%.3f" % [cue, first, last])
	_check(
		looked > 1300 and clicks.is_empty(),
		(
			"every cue starts and ends at silence (%d looked at; clicks: %s)"
			% [looked, ", ".join(clicks)]
		)
	)
	_check(seams.is_empty(), "every loop's end runs into its start (%s)" % ", ".join(seams))


## RMS of a cue in dB, from every fourth sample.
static func _level(data: PackedByteArray) -> float:
	var sum := 0.0
	var n := 0
	for i in range(0, data.size() - 1, 8):
		var v := data.decode_s16(i) / 32768.0
		sum += v * v
		n += 1
	return 10.0 * log(maxf(sum / maxf(n, 1.0), 1e-12)) / log(10.0)


func _clean(main) -> void:
	var assets: Assets = main.sound.assets
	if not DirAccess.dir_exists_absolute(final_dir):
		_check(true, "(no audio_src/final/sfx beside the project: CLEAN levels not measured)")
		return
	var worst := 0.0
	var worst_cue := ""
	var pairs := 0
	for cue: String in assets.sfx_index:
		if not cue.ends_with("_clean"):
			continue
		var base := cue.trim_suffix("_clean")
		var a := _pcm(cue)
		var b := _pcm(base)
		if a.is_empty() or b.is_empty():
			continue
		pairs += 1
		# Over the cussing take's length: a CLEAN line that ends on its cover
		# rings a little longer.
		var off := _level(a.slice(0, b.size())) - _level(b)
		if absf(off) > absf(worst):
			worst = off
			worst_cue = cue
	_check(
		pairs > 100 and absf(worst) <= CLEAN_DB,
		(
			"every CLEAN copy is as loud as its cussing take (%d; furthest %s %+.1f dB)"
			% [pairs, worst_cue, worst]
		)
	)


func _music(main) -> void:
	var sound: Sound = main.sound
	var sp := sound.score_player
	var full := sound.music_gain
	sound.set_radio(false)
	sound.level_music(full * .8)
	_check(absf(sp.master - full * .8) < .001, "play's own hold on the music (%.3f)" % sp.master)
	sound._music_duck = Sound.MUSIC_UNDER_DJ
	sound.level_music(full * .8)
	_check(
		absf(sp.master - full * .8 * Sound.MUSIC_UNDER_DJ) < .001,
		"Dub over the song still holds the music down under play's ticks (%.3f)" % sp.master
	)
	sound._music_duck = 1.0
	sound.set_radio(true, .5, 0.0)
	var radio := sound.radio_gain
	sound.level_music(full)
	_check(
		radio > 0.0 and absf(sp.master - full * (1.0 - radio)) < .001,
		"a jukebox playing still holds the music down under play's ticks (%.3f)" % sp.master
	)
	sound.set_radio(false)
	sound.set_score("music")
	sound.level_music(full * .5)
	sound.set_score("title")
	_check(absf(sp.master - full) < .001, "back to the menus the music is whole (%.3f)" % sp.master)


func _barks(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	var barks = g.features.get("enemy_barks")
	_check(barks != null, "the hands' barks are on")
	if barks == null:
		return
	var dice := RandomNumberGenerator.new()
	dice.seed = 9
	var repeats := 0
	var last := -1
	for i in 400:
		var count := 2 + i % 2
		var n: int = barks._fresh("hick/spot", dice.randi_range(0, count - 1), count)
		if n == last:
			repeats += 1
		last = n
	_check(repeats == 0, "a hand never says the same line twice running (%d repeats)" % repeats)
	_check(barks._fresh("one/line", 0, 1) == 0, "a moment with one line still says it")
