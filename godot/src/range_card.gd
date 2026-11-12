## The firing range's station card: a tin plate in the top left corner of the
## view naming the station the player stands at, what it teaches (for the
## first few seconds there), and what it has measured: hits, groupings,
## pellets on each board, damage by gun, how long a critter took to drop and
## what the county's hands are up to. Drawn in the HUD's panel and lettering,
## so it reads the same in software and on the Godot 2D canvas.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const Targets := preload("res://src/range_targets.gd")
const X := 4
const Y := 18
const W := 150
## Seconds the teaching lines stay up after the player arrives.
const TEACH_FOR := 9.0
const READ := Color(250 / 255.0, 214 / 255.0, 150 / 255.0)
const GOOD := Color(160 / 255.0, 236 / 255.0, 120 / 255.0)


static func draw(c: Canvas, f) -> void:
	var game = f.game
	var info: Dictionary = L.STATIONS[f.station]
	var talking: bool = game.message_until > game.clock
	# Under the notice banner while one is up, and short.
	var top := 34 if talking else Y
	var teach: Array = []
	if game.clock - f.station_since < TEACH_FOR and not talking:
		for line: String in info["teach"]:
			teach.append_array(PixelType.wrap(line, W - 10, "mini"))
	var readings: Array = readouts(f)
	var height := 14 + teach.size() * 7 + readings.size() * 7 + (3 if not teach.is_empty() else 0)
	HUD.panel(c, X, top, W, height, Color(34 / 255.0, 24 / 255.0, 19 / 255.0))
	HUD.text(c, String(info["title"]), X + 5, top + 3, "body", HUD.AMBER)
	var y := top + 13
	for line: String in teach:
		HUD.text(c, line, X + 5, y, "mini", HUD.INK, false, false)
		y += 7
	if not teach.is_empty():
		c.fill_rect(X + 5, y, W - 10, 1, Color(110 / 255.0, 80 / 255.0, 54 / 255.0))
		y += 3
	for row in readings:
		var text := String(row[0]) if row is Array else String(row)
		var colour: Color = row[1] if row is Array else READ
		HUD.text(c, text, X + 5, y, "mini", colour, false, false)
		if row is Array and row.size() > 2:
			# A bar: how soaked, how much health is left.
			var share := clampf(float(row[2]), 0.0, 1.0)
			c.fill_rect(X + W - 34, y + 1, 28, 3, Color(.2, .14, .1))
			c.fill_rect(X + W - 34, y + 1, int(28 * share), 3, colour)
		y += 7


## The station's measurements as lines (a line may be [text, colour] or
## [text, colour, bar share]).
static func readouts(f) -> Array:
	var game = f.game
	var t = f.targets
	var out: Array = []
	match String(f.station):
		"cans":
			var up := 0
			for can: Array in L.CANS:
				if not game.scenery_spent.has(String(can[0])):
					up += 1
			out.append("CANS STANDING %d OF %d" % [up, L.CANS.size()])
			for target: Dictionary in _targets_of(t, "cans"):
				out.append(
					(
						"%d YD BOARD  %d HITS  GROUP %d IN"
						% [_yards(game, target), int(target["hits"]), Targets.grouping(target)]
					)
				)
		"pellets":
			var parts := PackedStringArray()
			for target: Dictionary in _targets_of(t, "pellets"):
				parts.append(
					(
						"%d YD %d"
						% [
							int(String(target["id"]).get_slice("-", 1)),
							int(f.pellet_blast.get(target["id"], 0))
						]
					)
				)
			out.append("LAST BLAST, PELLETS ON EACH BOARD:")
			out.append([" ".join(parts), GOOD])
			out.append("ONE BARREL 10, BOTH 20")
		"rifle":
			var parts2 := PackedStringArray()
			for target: Dictionary in _targets_of(t, "rifle"):
				parts2.append(
					"%s:%d" % [String(target["id"]).get_slice("-", 1), int(target["hits"])]
				)
			out.append("GONG HITS  " + " ".join(parts2))
			out.append(["BARREL HEAT %d%%" % roundi(game.armory.rifle_heat * 100.0), _heat(game)])
		"gallery":
			if t.gallery_on:
				out.append(
					[
						(
							"SCORE %d  HITS %d  SHOTS %d"
							% [t.gallery_score, t.gallery_hits, t.gallery_shots]
						),
						GOOD
					]
				)
				out.append("TIME LEFT %d" % ceili(L.GALLERY_TIME - t.gallery_clock))
			else:
				out.append("PULL THE LEVER TO START A ROUND")
				if t.gallery_last != "":
					out.append("LAST: " + t.gallery_last)
			out.append("BEST THIS VISIT %d" % t.gallery_best)
		"bowling":
			out.append("PINS STANDING %d OF 10" % (t.pins.size() - t.pins_down()))
			out.append("STRIKES %d  SPARES %d" % [t.strikes, t.spares])
			if t.last_roll != "":
				out.append([t.last_roll, GOOD])
		"soak":
			out.append_array(_critters(f, "soak", true))
			out.append("SLIPS IN THE MILK %d" % f.slips)
		"special":
			var latest: Dictionary = _latest(t, "special")
			if not latest.is_empty():
				out.append(_hit_line(latest))
			out.append("WIND-UPS BROKEN %d" % f.interrupts)
			out.append_array(_critters(f, "special", false))
		"pit":
			var left := 0
			for d: Vector2 in L.DRUMS:
				if game.drums.has(d):
					left += 1
			out.append("BLASTS %d  GIBBED %d" % [f.blasts, f.gibs])
			out.append("BEST CHAIN %d  DRUMS LEFT %d" % [maxi(f.best_chain, f.chain), left])
			out.append("FODDER STANDING %d" % f._count("pit"))
		"yard":
			var hit: Dictionary = _latest(t, "yard")
			if not hit.is_empty():
				out.append(_hit_line(hit))
				out.append(["DAMAGE A SECOND %d" % Targets.dps(hit, game.clock), GOOD])
			out.append("SPRINT ON MOONSHINE FOR A SQUARE HIT")
		"bullpen", "corral":
			out.append_array(_critters(f, String(f.station), false))
			if out.is_empty():
				out.append("PULL A LEVER ON THE FENCE")
			if not f.kills.is_empty():
				out.append([String(f.kills[0]), GOOD])
		"armory":
			var guns: Array = f.damage_by_gun.keys()
			guns.sort_custom(func(a, b): return f.damage_by_gun[a] > f.damage_by_gun[b])
			out.append("SHOTS FIRED THIS VISIT %d" % f.shots_fired)
			if guns.is_empty():
				out.append("NO DAMAGE DEALT YET")
			for k in mini(3, guns.size()):
				out.append("%s %d" % [String(guns[k]), roundi(float(f.damage_by_gun[guns[k]]))])
	if game.clock < f.reach_until and String(f.station) in ["cans", "rifle", "pellets", "special"]:
		out.append([f.reach_note, GOOD])
	return out


static func _targets_of(t, station: String) -> Array:
	var out: Array = []
	for target: Dictionary in t.targets:
		if String(target["station"]) == station:
			out.append(target)
	return out


## The station's target hit last.
static func _latest(t, station: String) -> Dictionary:
	var best := {}
	var most := 0.0
	for target: Dictionary in _targets_of(t, station):
		if target["dps"].is_empty():
			continue
		var at := float(target["dps"][target["dps"].size() - 1][0])
		if at > most:
			most = at
			best = target
	return best


static func _hit_line(target: Dictionary) -> String:
	var last: Array = target["last"]
	if last.is_empty():
		return ""
	var gun := String(Weapons.LABELS[int(last[0])]).get_slice(" [", 0)
	if float(last[1]) < 0.0:
		return "BLAST AT %d YDS" % roundi(float(last[2]))
	return "%s %d A HIT AT %d YDS" % [gun, roundi(float(last[1])), roundi(float(last[2]))]


static func _yards(game, target: Dictionary) -> int:
	return roundi(Vector2(target["x"] - game.player.x, target["y"] - game.player.y).length())


static func _heat(game) -> Color:
	return HUD.LOW if game.armory.rifle_heat > .6 else READ


## The critters a station turned out: name, health or soak, what they are doing.
static func _critters(f, station: String, soak: bool) -> Array:
	var out: Array = []
	for foe: Enemy in f.watched:
		var w: Dictionary = f.watched[foe]
		if String(w["station"]) != station or not foe.alive:
			continue
		var name := String(L.NAMES.get(foe.kind, foe.kind.to_upper()))
		var doing: String = f.doing_words(foe)
		if soak:
			out.append(
				["%s SOAK %d%%  %s" % [name, roundi(foe.soak * 100.0), doing], READ, foe.soak]
			)
		else:
			out.append(["%s  %s" % [name, doing], READ, foe.hp / maxf(1.0, foe.max_hp)])
		if out.size() >= 4:
			break
	return out
