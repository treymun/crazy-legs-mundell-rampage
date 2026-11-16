## The spoken lines, headless (no window, no audio device): every line the
## game can say has its finished file and loads from the packed bank at a sane
## length; every caption the game shows for a line is the text the line was
## made from (audio_src/manifest.json); every recording, transcript and
## take is booked in the ElevenLabs ledger, and the ledger adds up.
##
##   Godot --headless --path <project> --script res://tools/voice_check.gd
##
## Reads the repository's audio_src/ beside godot/ (like pack_assets.gd) and
## the packed godot/assets_gen bank; run pack_assets.gd after a voice pass.
extends SceneTree

## Seconds a finished line may last: shorter is a clipped word, longer is the
## voice model rambling past the caption (audio_build.py cuts at the last word).
const SHORTEST := .3
const LONGEST := 6.0
const CEILING := 100000
## Lines whose recording is a byte-for-byte copy of another line's booked
## take (no request of their own): line -> the take's recording.
const COPIED := {"county_dispatch_6": "county_dispatch_4.take3"}
const SPEECH := ["talk_", "bark_", "cuss_", "boss_", "mundell_", "county_", "range_pa_", "ann_"]

var failures: Array = []
var repo := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var manifest := _json("audio_src/manifest.json")
	var ledger := _json("audio_src/ledger.json")
	var cues: Dictionary = manifest.get("cues", {})
	var spoken := {}
	for name: String in cues:
		var origin := str((cues[name] as Dictionary).get("origin", ""))
		if origin == "generated speech":
			spoken[name] = cues[name]
	print("\nVOICES (%d spoken lines in the manifest)" % spoken.size())
	_check(spoken.size() > 300, "the manifest lists the spoken lines (%d)" % spoken.size())
	_files(spoken, cues)
	_bank(spoken, cues)
	_captions(cues)
	_ledger(spoken, ledger)
	print("")
	print("VOICE CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(repo.path_join(path))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_check(false, "%s reads" % path)
		return {}
	return parsed


static func _speech(cue: String) -> bool:
	for prefix: String in SPEECH:
		if cue.begins_with(prefix):
			return true
	return false


## Each spoken line: built from its transcript (cut at the caption's words),
## measured clean, its recording, transcript and finished file on disk.
func _files(spoken: Dictionary, cues: Dictionary) -> void:
	var bad: Array = []
	for name: String in spoken:
		var c: Dictionary = spoken[name]
		var recipe: Dictionary = c.get("recipe", {})
		var why := ""
		if str(c.get("validation", "")) != "ok":
			why = str(c.get("validation", ""))
		elif not recipe.has("words_at"):
			why = "not cut at its words"
		elif not FileAccess.file_exists(repo.path_join("audio_src/final/sfx/%s.wav" % name)):
			why = "no finished file"
		elif not FileAccess.file_exists(repo.path_join("audio_src/generated/tts/%s.mp3" % name)):
			why = "no recording"
		elif not FileAccess.file_exists(repo.path_join("audio_src/generated/stt/%s.json" % name)):
			why = "no transcript"
		else:
			var at: Array = recipe["words_at"]
			var a: float = at[0]
			var b: float = at[1]
			if b - a < .2:
				why = "its words last %.2f s" % (b - a)
		if why != "":
			bad.append("%s (%s)" % [name, why])
	_check(bad.is_empty(), "every spoken line is mastered from its transcript %s" % [bad])
	var clean_missing: Array = []
	for name: String in spoken:
		if name.begins_with("cuss_") and not cues.has(name + "_clean"):
			clean_missing.append(name)
		elif name.begins_with("cuss_"):
			var copy: Dictionary = cues[name + "_clean"]
			if str(copy.get("validation", "")) != "ok":
				clean_missing.append(name + "_clean")
	_check(clean_missing.is_empty(), "every cuss line has its CLEAN copy %s" % [clean_missing])


## Each spoken line (and CLEAN copy) loads from the packed bank at a sane length.
func _bank(spoken: Dictionary, cues: Dictionary) -> void:
	var art := Assets.new()
	var bad: Array = []
	var seconds := 0.0
	var count := 0
	for name: String in cues:
		if not spoken.has(name) and not (name.ends_with("_clean") and _speech(name)):
			continue
		count += 1
		var wav := art.cue(name)
		if wav == null:
			bad.append(name + " (not in the bank)")
			continue
		var length := wav.get_length()
		seconds += length
		if length < SHORTEST or length > LONGEST:
			bad.append("%s (%.2f s)" % [name, length])
	_check(
		bad.is_empty(),
		(
			"%d lines load from the bank, %.2f s each on average, all %.1f to %.1f s %s"
			% [count, seconds / maxf(1.0, count), SHORTEST, LONGEST, bad]
		)
	)


## Every caption the game shows for a line is the text the line was made from.
func _captions(cues: Dictionary) -> void:
	var said := {}  # cue -> caption
	var bosses = load("res://src/features/boss_voices.gd")
	for who: String in bosses.LINES:
		var lines: Array = bosses.LINES[who]
		_check(
			lines.size() == bosses.MOMENTS.size(),
			"%s has a line for every boss moment (%d)" % [who, lines.size()]
		)
		for i in mini(lines.size(), bosses.MOMENTS.size()):
			said["boss_%s_%s" % [who, bosses.MOMENTS[i]]] = str(lines[i])
	for cue: String in bosses.MAW_LINES:
		said[cue] = str(bosses.MAW_LINES[cue])
	for speaker: Variant in bosses.SPEAKERS.values():
		_check(bosses.LINES.has(speaker), "boss voice %s has lines" % speaker)
	var barks = load("res://src/features/enemy_barks.gd")
	var moments: Array = (barks.LINES["hick"] as Dictionary).keys()
	moments.sort()
	for who: String in barks.LINES:
		var by_moment: Dictionary = barks.LINES[who]
		var mine: Array = by_moment.keys()
		mine.sort()
		_check(mine == moments, "the %s voice has a line for every squad moment" % who)
		for moment: String in by_moment:
			var lines: Array = by_moment[moment]
			for n in lines.size():
				said["bark_%s_%s_%d" % [who, moment, n]] = str(lines[n])
	var unvoiced: Array = []
	for kind: String in barks.VOICES:
		if not barks.LINES.has(barks.VOICES[kind]):
			unvoiced.append(kind)
	_check(unvoiced.is_empty(), "every talking kind's voice has lines %s" % [unvoiced])
	var variants = load("res://src/features/variants_feature.gd")
	for kind: String in variants.TOUGH_SAYS:
		_check(Enemy.DEFS.has(kind), "tough guy %s is an enemy kind" % kind)
		said["bark_" + kind] = str(variants.TOUGH_SAYS[kind])
	for kind: String in Enemy.DEFS:
		if (Enemy.DEFS[kind] as Dictionary).has("tough_for"):
			_check(variants.TOUGH_SAYS.has(kind), "tough guy %s has his line" % kind)
	var game_script = load("res://src/game.gd")
	for n in (game_script.FAIR_PA as Array).size():
		said["ann_fair_%d" % n] = str(game_script.FAIR_PA[n])
	var mundell: Dictionary = load("res://src/barks.gd").spoken_lines()
	for moment: String in mundell:
		var lines: Array = mundell[moment]
		for n in lines.size():
			said["mundell_%s_%d" % [moment, n]] = str(lines[n])
	var pack := CussLines.data()
	for group: String in ["enemies", "tactical"]:
		var by_voice: Dictionary = pack.get(group, {})
		for who: String in by_voice:
			_cuss_lines(said, who, by_voice[who])
	_cuss_lines(said, "mundell", pack.get("mundell", {}))
	# The county radio (pass 8): Dub's lines, the scanner's, Dub's crude ones.
	var radio := RadioStation.data()
	var radio_count := 0
	for part: Array in [["dj", "dj_"], ["scanner", "scan_"]]:
		var groups: Dictionary = radio.get(part[0], {})
		for group: String in groups:
			var lines: Array = groups[group]
			for n in lines.size():
				said["%s%s_%d" % [part[1], group, n]] = str(lines[n])
				radio_count += 1
	_cuss_lines(said, "dj", radio.get("cuss", {}))
	_check(radio_count >= 80, "the county radio's lines are in the list (%d)" % radio_count)
	var wrong: Array = []
	for cue: String in said:
		if not cues.has(cue):
			wrong.append(cue + " (not made)")
		elif str((cues[cue] as Dictionary).get("prompt", "")) != str(said[cue]):
			wrong.append("%s (made as %s)" % [cue, (cues[cue] as Dictionary).get("prompt", "")])
	_check(
		wrong.is_empty(),
		"%d captions are the words their lines were made from %s" % [said.size(), wrong]
	)


func _cuss_lines(said: Dictionary, who: String, moments: Dictionary) -> void:
	for moment: String in moments:
		var lines: Array = moments[moment]
		for n in lines.size():
			said["cuss_%s_%s_%d" % [who, moment, n]] = str(lines[n]).replace("*", "")


## Every recording and transcript is a settled request in the ledger, and the
## ledger adds up: nothing pending, the last reconcile matching the account,
## under the ceiling.
func _ledger(spoken: Dictionary, ledger: Dictionary) -> void:
	var entries: Array = ledger.get("entries", [])
	var booked := {}  # "kind/name" -> settled count
	var total := 0
	var pending := 0
	for e: Dictionary in entries:
		var actual: int = int(e.get("actual", 0))
		if str(e.get("status", "")) == "pending":
			pending += 1
			continue
		total += actual
		if str(e.get("status", "")) == "settled" and str(e.get("name", "")) != "":
			var key := "%s/%s" % [e["kind"], e["name"]]
			booked[key] = int(booked.get(key, 0)) + 1
	var unbooked: Array = []
	for name: String in spoken:
		if COPIED.has(name):
			var dir := repo.path_join("audio_src/generated/tts/")
			var same := (
				FileAccess.get_file_as_bytes(dir + name + ".mp3")
				== FileAccess.get_file_as_bytes(dir + str(COPIED[name]) + ".mp3")
			)
			_check(same, "%s is a copy of the booked take %s" % [name, COPIED[name]])
			continue
		for kind: String in ["tts", "stt"]:
			if not booked.has("%s/%s" % [kind, name]):
				unbooked.append("%s/%s" % [kind, name])
	_check(unbooked.is_empty(), "every line's recording and transcript is booked %s" % [unbooked])
	# Every take kept beside a line (<name>.take<k>.mp3) is one more booked request.
	var takes: Array = []
	for file: String in DirAccess.get_files_at(repo.path_join("audio_src/generated/tts")):
		var parts := file.get_basename().split(".take")
		if parts.size() == 2 and spoken.has(parts[0]):
			var k := int(parts[1])
			if int(booked.get("tts/" + parts[0], 0)) < k + 1:
				takes.append(file)
	_check(takes.is_empty(), "every kept take is booked %s" % [takes])
	_check(pending == 0, "nothing pending in the ledger (%d)" % pending)
	_check(total <= CEILING, "the ledger's total %d is under the %d ceiling" % [total, CEILING])
	var reconciled: Dictionary = ledger.get("reconciled", {})
	var drop: int = int(reconciled.get("account_drop", -1))
	_check(
		drop == total,
		"the ledger matches the account's drop at its last reconcile (%d = %d)" % [total, drop]
	)
