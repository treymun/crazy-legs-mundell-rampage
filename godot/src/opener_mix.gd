## The chapter openers' sound (opener.gd; the numbers in openers.json "mix"):
## no dead air. Under the whole opener runs the chapter's own song from its
## top, the bed: Sound's score player plays it as the chapter's music, held
## low (Sound.set_opener_hold) and ducked under every spoken line (the music
## duck of pass 9), swelling into the title card and the boss's reveal and
## dipping under the boss's own sting; at the end it is simply let up to play's
## level, the same stream going on, so there is no gap and no second song.
## Under the flyover: the ambience the camera flies over (a shot's "amb", the
## chapter's own bed), its rain where it rains, the level's far-off sounds as
## the camera passes them, a shot's own spot sounds; a whoosh at each cut and
## at the landing, a hit as the title card lands, a low swell for the reveal.
##
## plan() is the whole mix laid out in time (opener_check holds it to: a bed
## from start to end, no stretch of more than GAP seconds with nothing
## sounding); tools/opener_check.gd -- plan <file> writes it for measuring.
## Looks (and sounds) only.
class_name OpenerMix
extends RefCounted

## The longest a plan may go with nothing sounding (seconds).
const GAP := .5

## The song under the opener, and the bed's hold at its keys ([t, share]).
var song := ""
var bed: Array = []
## What to play: [time, kind, cue, volume, pan], in time order. Kinds: voice,
## effect, sting, amb (Sound.set_room), rain (the rain bed's level).
var cues: Array = []
## The ambience the opener leaves on for play (play sets its own a tick later).
var last_amb := ""


static func settings() -> Dictionary:
	return ChapterOpener.data().get("mix", {})


static func number(key: String, otherwise: float) -> float:
	var value: float = settings().get(key, otherwise)
	return value


## The song for `chapter` (its "song", else the first of its score's tracks).
static func song_of(chapter: String, score: String) -> String:
	var e := ChapterOpener.entry(chapter)
	if e.has("song"):
		return str(e["song"])
	var tracks: Array = Sound.SCORES.get(score, [score])
	return str(tracks[0]) if not tracks.is_empty() else score


## The mix for opener `op` (its schedule worked out), from its own camera.
func build(op: ChapterOpener, m: MainState) -> void:
	var e := ChapterOpener.entry(op.chapter)
	var g := op.game
	song = song_of(op.chapter, g.level.score)
	cues = []
	var keys: Dictionary = settings().get("bed", {})
	var card_land := op.title_land()
	var sting_secs := op.seconds(m, op.boss_sting(), 2.2)
	bed = [
		[0.0, _k(keys, "start", .6)],
		[maxf(.5, card_land - .5), _k(keys, "start", .6)],
		[card_land, _k(keys, "card", 1.0)],
		[card_land + 1.4, _k(keys, "between", .85)],
		[maxf(card_land + 1.5, op.boss_at - 1.6), _k(keys, "between", .85)],
		[op.boss_at, _k(keys, "reveal", 1.2)],
		[op.boss_at + .45, _k(keys, "between", .85)],
		[maxf(op.boss_at + .5, op.growl_at - .2), _k(keys, "between", .85)],
		[op.growl_at, _k(keys, "dip", .35)],
		[op.growl_at + sting_secs, _k(keys, "dip", .35)],
		[op.land_at, _k(keys, "land", .7)],
		[op.length, 1.0],
	]
	for n in op.lines_count():
		cues.append([op.narr_at(n), "voice", "narr_%s_%d" % [op.chapter, n], 1.0, 0.0])
	var boss: Dictionary = e.get("boss", {})
	cues.append([op.growl_at, "effect", str(boss.get("growl", "")), .9, 0.0])
	cues.append([op.growl_at, "sting", op.boss_sting(), number("sting_gain", .6), 0.0])
	cues.append([op.line_at, "voice", str(boss.get("line", "")), 1.0, 0.0])
	# The card's hit, the reveal's swell, a whoosh at each cut and the landing.
	var hit := str(e.get("hit", "opener_%s_hit" % op.chapter))
	var hit_lead: float = e.get("hit_lead", 0.0)
	cues.append([maxf(0.0, card_land - hit_lead), "effect", hit, number("hit_gain", .8), 0.0])
	var reveal := str(settings().get("reveal", ""))
	cues.append(
		[
			maxf(0.0, op.boss_at - number("reveal_lead", .3)),
			"effect",
			reveal,
			number("reveal_gain", .8),
			0.0
		]
	)
	var whooshes: Array = settings().get("whoosh", [])
	var cuts: Array = []
	for k in range(1, op.starts().size()):
		cuts.append(op.starts()[k])
	cuts.append(op.land_at)
	var lead := number("whoosh_lead", .3)
	for k in cuts.size():
		if whooshes.is_empty():
			break
		var when: float = cuts[k]
		var pan := -.35 if k % 2 == 0 else .35
		var name := str(whooshes[k % whooshes.size()])
		cues.append([maxf(0.0, when - lead), "effect", name, number("whoosh_gain", .5), pan])
	_beds(op, g, e)
	_spots(op, g, e)
	cues.sort_custom(ChapterOpener.sooner.bind(0))


static func _k(keys: Dictionary, key: String, otherwise: float) -> float:
	var value: float = keys.get(key, otherwise)
	return value


## The ambience under each shot (its "amb", else the chapter's, else the
## level's own or the yard), the rain where it rains, and play's room for
## the landing.
func _beds(op: ChapterOpener, g: Game, e: Dictionary) -> void:
	var level_bed := g.level.ambience if g.level.ambience != "" else "yard"
	var chapter_bed := str(e.get("amb", level_bed))
	var shots := ChapterOpener.shots_of(op.chapter)
	var playing := ""
	for k in shots.size():
		var shot: Dictionary = shots[k]
		var amb := str(shot.get("amb", chapter_bed))
		if amb != playing:
			cues.append([op.starts()[k], "amb", amb, 1.0, 0.0])
			playing = amb
	var cell := g.world.cell(g.player.x, g.player.y)
	var home := g.level.ambience
	if home == "":
		home = "room" if g.world.roof[cell] != 0.0 else "yard"
	if home != playing:
		cues.append([op.land_at, "amb", home, 1.0, 0.0])
	last_amb = home
	var weather: GameFeature = g.features.get("weather")
	var rain := 0.0
	if weather != null:
		rain = weather.get("rain")
	if rain > 0.0:
		cues.append([0.0, "rain", "rain_loop", rain * .9 * Sound.OPENER_AMB, 0.0])


## The level's far-off sounds (its distant cues) each played once as the
## flyover passes nearest them, placed from the camera; and a shot's own
## spot sounds ([seconds into the shot, cue, volume, pan]).
func _spots(op: ChapterOpener, g: Game, e: Dictionary) -> void:
	var reach := number("spot_reach", 16.0)
	var gain := number("spot_gain", .55)
	var nearest := {}
	var t := 0.0
	while t < op.boss_at:
		var eye := op.eye_at(t)
		var ex: float = eye["x"]
		var ey: float = eye["y"]
		for row: Array in g.world.distant_cues:
			var cue := str(row[2])
			var cx: float = row[0]
			var cy: float = row[1]
			var d := Vector2(cx - ex, cy - ey).length()
			var best: Array = nearest.get(cue, [INF])
			var best_d: float = best[0]
			if d < reach and d < best_d:
				var heading: float = eye["view_angle"]
				var turn := angle_difference(heading, atan2(cy - ey, cx - ex))
				nearest[cue] = [d, t, sin(turn)]
		t += .1
	for cue: String in nearest:
		var found: Array = nearest[cue]
		var d: float = found[0]
		var when: float = found[1]
		var pan: float = found[2]
		var volume := gain * clampf(1.2 - d / reach, .25, 1.0)
		cues.append([maxf(.2, when - .4), "effect", cue, volume, pan * .8])
	var shots := ChapterOpener.shots_of(op.chapter)
	for k in shots.size():
		var shot: Dictionary = shots[k]
		for spot: Variant in shot.get("spots", []):
			var s: Array = spot
			var at: float = s[0]
			var volume: float = s[2] if s.size() > 2 else gain
			var pan: float = s[3] if s.size() > 3 else 0.0
			cues.append([op.starts()[k] + at, "effect", str(s[1]), volume, pan])
	for spot: Variant in e.get("spots", []):
		var s: Array = spot
		var at: float = s[0]
		var volume: float = s[2] if s.size() > 2 else gain
		var pan: float = s[3] if s.size() > 3 else 0.0
		cues.append([at, "effect", str(s[1]), volume, pan])


## The bed's hold at `t`.
func bed_at(t: float) -> float:
	if bed.is_empty():
		return 1.0
	var prev: Array = bed[0]
	for key: Array in bed:
		var kt: float = key[0]
		if t < kt:
			var pt: float = prev[0]
			var pv: float = prev[1]
			var kv: float = key[1]
			return lerpf(pv, kv, smoothstep(pt, kt, t)) if kt > pt else kv
		prev = key
	var last: float = prev[1]
	return last


## The whole mix laid out in time, at the gains `sound` plays at now:
## {length, song, duck, bed: [[t, gain]], rows: [{at, until, cue, lane, gain}]}.
func plan(op: ChapterOpener, m: MainState) -> Dictionary:
	var s: Sound = m.sound
	var rows: Array = []
	var amb_rows: Array = []
	for c: Array in cues:
		var at: float = c[0]
		var kind := str(c[1])
		var cue := str(c[2])
		var volume: float = c[3]
		if cue == "":
			continue
		var row := {"at": at, "cue": cue}
		match kind:
			"voice":
				row["lane"] = "voice"
				row["gain"] = volume * s.voice_gain * .88 * s.mix_headroom
				row["until"] = at + op.seconds(m, cue, 0.0)
			"effect":
				row["lane"] = "spot"
				row["gain"] = minf(1.0, s.effects_gain * volume) * .82 * s.mix_headroom
				row["until"] = at + op.seconds(m, cue, 0.0)
			"sting":
				row["lane"] = "music"
				row["gain"] = .84 * s.music_gain * volume
				row["until"] = minf(op.length, at + op.seconds(m, cue, 0.0))
				row["ducked"] = true
			"amb":
				row["cue"] = "amb_" + cue
				row["lane"] = "amb"
				row["gain"] = .78 * s.ambient_gain * s.mix_headroom * Sound.OPENER_AMB
				row["loop"] = true
				amb_rows.append(row)
			"rain":
				row["lane"] = "amb"
				row["gain"] = minf(1.0, s.ambient_gain * volume) * .82 * s.mix_headroom
				row["loop"] = true
				row["until"] = INF
		rows.append(row)
	for k in amb_rows.size():
		var row: Dictionary = amb_rows[k]
		row["until"] = amb_rows[k + 1]["at"] if k + 1 < amb_rows.size() else INF
	var keys: Array = []
	for key: Array in bed:
		var share: float = key[1]
		keys.append([key[0], share * s.music_gain])
	return {
		"length": op.length,
		"song": song,
		"bed": keys,
		"duck": {"under": Sound.VOICE_DUCK, "down": Sound.DUCK_DOWN, "up": Sound.DUCK_UP},
		"rows": rows,
	}


## The stretches of a plan (from 0 to its length) with nothing sounding:
## [[from, to], ...] longer than `longest`.
static func silences(p: Dictionary, longest: float) -> Array:
	var spans: Array = []
	if str(p.get("song", "")) != "":
		var bed_keys: Array = p.get("bed", [])
		var lowest := INF
		for key: Array in bed_keys:
			var share: float = key[1]
			lowest = minf(lowest, share)
		if lowest > .01:
			spans.append([0.0, INF])
	for row: Dictionary in p.get("rows", []):
		var at: float = row["at"]
		var until: float = row.get("until", at)
		if until > at:
			spans.append([at, until])
	spans.sort_custom(ChapterOpener.sooner.bind(0))
	var out: Array = []
	var covered := 0.0
	var length: float = p.get("length", 0.0)
	for span: Array in spans:
		var a: float = span[0]
		var b: float = span[1]
		if a - covered > longest and covered < length:
			out.append([covered, minf(a, length)])
		covered = maxf(covered, b)
	if length - covered > longest:
		out.append([covered, length])
	return out
