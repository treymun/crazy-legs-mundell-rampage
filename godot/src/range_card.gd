## The firing range's station card: a tin plate in the top left corner of the
## view naming the station the player stands at, what it teaches (for the
## first few seconds there), and what it has measured: hits, groupings,
## pellets on each board, damage by gun, how long a critter took to drop and
## what the county's hands are up to; at a game, its score, the player's best
## and, once the teaching lines are gone, the county's top five from the
## lobby server (range_board.gd). Drawn in the HUD's panel and lettering, so
## it reads the same in software and on the Godot 2D canvas.
extends RefCounted

const L := preload("res://src/range_layout.gd")
const Targets := preload("res://src/range_targets.gd")
const FiringRange := preload("res://src/features/firing_range.gd")
const Games := preload("res://src/range_games.gd")
const Skee := preload("res://src/range_skeeball.gd")
const X := 4
## Stations whose target stands straight ahead and high (the skee-ball
## board): their card goes in the top right corner instead.
const RIGHT := ["skeeball"]
const Y := 18
const W := 150
## Seconds the teaching lines stay up after the player arrives.
const TEACH_FOR := 9.0
const READ := Color(250 / 255.0, 214 / 255.0, 150 / 255.0)
const GOOD := Color(160 / 255.0, 236 / 255.0, 120 / 255.0)


static func draw(c: Canvas, f: FiringRange) -> void:
	var game: Game = f.game
	var x := 320 - W - 4 if RIGHT.has(String(f.station)) else X
	var info: Dictionary = L.STATIONS[f.station]
	var talking: bool = game.message_until > game.clock
	# Under the notice banner while one is up, and short.
	var top := 34 if talking else Y
	var teach: Array = []
	if game.clock - f.station_since < TEACH_FOR and not talking:
		for line: String in info["teach"]:
			teach.append_array(PixelType.wrap(line, W - 10, "mini"))
	var readings: Array = readouts(f)
	if teach.is_empty():
		readings.append_array(board_lines(f))
	var height := 14 + teach.size() * 7 + readings.size() * 7 + (3 if not teach.is_empty() else 0)
	HUD.panel(c, x, top, W, height, Color(34 / 255.0, 24 / 255.0, 19 / 255.0))
	HUD.text(c, str(info["title"]), x + 5, top + 3, "body", HUD.AMBER)
	var y := top + 13
	for line: String in teach:
		HUD.text(c, line, x + 5, y, "mini", HUD.INK, false, false)
		y += 7
	if not teach.is_empty():
		c.fill_rect(x + 5, y, W - 10, 1, Color(110 / 255.0, 80 / 255.0, 54 / 255.0))
		y += 3
	for row: Variant in readings:
		var text := str(row[0]) if row is Array else str(row)
		var colour: Color = row[1] if row is Array else READ
		HUD.text(c, text, x + 5, y, "mini", colour, false, false)
		var parts: Array = row if row is Array else []
		if row is Array and parts.size() > 2:
			# A bar: how soaked, how much health is left.
			var bar: float = parts[2]
			var share := clampf(bar, 0.0, 1.0)
			c.fill_rect(x + W - 34, y + 1, 28, 3, Color(.2, .14, .1))
			c.fill_rect(x + W - 34, y + 1, int(28 * share), 3, colour)
		y += 7


## The station's measurements as lines (a line may be [text, colour] or
## [text, colour, bar share]).
static func readouts(f: FiringRange) -> Array:
	var game: Game = f.game
	var t := f.targets
	var out: Array = []
	match String(f.station):
		"cans":
			var up := 0
			for can: Array in L.CANS:
				if not game.scenery_spent.has(str(can[0])):
					up += 1
			out.append("CANS STANDING %d OF %d" % [up, L.CANS.size()])
			for target: Dictionary in _targets_of(t, "cans"):
				var yards := _yards(game, target)
				var hits: int = target["hits"]
				out.append(
					"%d YD BOARD  %d HITS  GROUP %d IN" % [yards, hits, Targets.grouping(target)]
				)
		"pellets":
			var parts := PackedStringArray()
			for target: Dictionary in _targets_of(t, "pellets"):
				var pellets: int = f.pellet_blast.get(target["id"], 0)
				parts.append("%d YD %d" % [int(str(target["id"]).get_slice("-", 1)), pellets])
			out.append("LAST BLAST, PELLETS ON EACH BOARD:")
			out.append([" ".join(parts), GOOD])
			out.append("ONE BARREL 10, BOTH 20")
		"rifle":
			var parts2 := PackedStringArray()
			for target: Dictionary in _targets_of(t, "rifle"):
				var gong_hits: int = target["hits"]
				parts2.append("%s:%d" % [str(target["id"]).get_slice("-", 1), gong_hits])
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
			var bowl := t.bowling
			out.append(
				(
					"FRAME %d  BALL %d  SCORE %d"
					% [mini(10, bowl.frame + 1), bowl.ball + 1, bowl.score()]
				)
			)
			out.append("PINS STANDING %d OF 10" % bowl.standing())
			if bowl.frame > 0 or bowl.ball > 0:
				out.append("SHEET  " + bowl.sheet_text())
			out.append(
				"STRIKES %d  SPARES %d  BEST GAME %d" % [bowl.strikes, bowl.spares, bowl.best_game]
			)
			if bowl.last_roll != "":
				out.append([bowl.last_roll, GOOD])
			else:
				out.append("TURN AS YOU LET GO TO HOOK IT")
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
				out.append([str(f.kills[0]), GOOD])
		"armory":
			var guns: Array = f.damage_by_gun.keys()
			guns.sort_custom(
				func(a: Variant, b: Variant) -> bool: return f.damage_by_gun[a] > f.damage_by_gun[b]
			)
			out.append("SHOTS FIRED THIS VISIT %d" % f.shots_fired)
			if guns.is_empty():
				out.append("NO DAMAGE DEALT YET")
			for k in mini(3, guns.size()):
				var dealt: float = f.damage_by_gun[guns[k]]
				out.append("%s %d" % [str(guns[k]), roundi(dealt)])
		"horseshoes", "dunk", "skeeball", "bottles":
			out.append_array(game_lines(f))
	if game.clock < f.reach_until and String(f.station) in ["cans", "rifle", "pellets", "special"]:
		out.append([f.reach_note, GOOD])
	return out


## The games row's lines.
static func game_lines(f: FiringRange) -> Array:
	var game: Game = f.game
	var g: Games = f.games
	var out: Array = []
	match String(f.station):
		"horseshoes":
			out.append(
				(
					"SHOE %d OF %d  SCORE %d  RINGERS %d"
					% [Games.SHOES - g.shoes_left, Games.SHOES, g.shoe_score, g.ringers]
				)
			)
			var court := game.world.elevation(L.STAKE.x, L.STAKE.y)
			var reach := Games.carry(game.player, court)
			var stake := Vector2(game.player.x, game.player.y).distance_to(L.STAKE)
			out.append("A PITCH CARRIES %.1f YDS, THE STAKE %.1f" % [reach, stake])
			if g.shoe_last != "":
				out.append([g.shoe_last, GOOD])
			out.append("BEST THIS VISIT %d" % g.shoe_best)
		"dunk":
			if g.dunk_on:
				out.append(
					[
						(
							"DUNKS %d  TIME LEFT %d"
							% [g.dunks, ceili(Games.DUNK_ROUND - g.dunk_clock)]
						),
						GOOD
					]
				)
			else:
				out.append("PULL THE LEVER FOR A ROUND")
			if g.dunk_last != "":
				out.append([g.dunk_last, GOOD])
			out.append("BEST THIS VISIT %d" % g.dunk_best)
		"skeeball":
			var skee: Skee = g.skee
			var ball := Skee.BALLS - skee.balls_left + (1 if skee.ball.is_empty() else 0)
			if skee.balls_left <= 0 and skee.ball.is_empty():
				ball = 1
			out.append("BALL %d OF %d  SCORE %d" % [mini(ball, Skee.BALLS), Skee.BALLS, skee.score])
			out.append(["HOW HARD", READ, Skee.power(game.player)])
			if skee.last != "":
				out.append([skee.last, GOOD])
			out.append("BEST THIS VISIT %d  FIFTIES %d" % [skee.best, skee.fifties])
		"bottles":
			var down := 0
			var off := 0
			for bottle: Dictionary in g.bottles:
				if str(bottle["gone"]) == "off":
					off += 1
				elif Games.bottle_down(bottle):
					down += 1
			out.append("BALLS LEFT %d  DOWN %d  OFF %d" % [g.balls_left, down, off])
			if g.bottle_last != "":
				out.append([g.bottle_last, GOOD])
			out.append("BEST THIS VISIT %d" % g.bottle_best)
	return out


## The station's game's best here and the county's top five (two to a line).
static func board_lines(f: FiringRange) -> Array:
	var out: Array = []
	var board := ""
	for key: String in FiringRange.BOARD_OF:
		if FiringRange.BOARD_OF[key] == String(f.station):
			board = key
	if board == "":
		return out
	var mine: int = f.records.get(board, 0)
	out.append("YOUR BEST EVER %d" % mine)
	var rows := RangeBoard.rows(board)
	if rows.is_empty():
		out.append("COUNTY BOARD: ASKING..." if RangeBoard.busy() else "COUNTY BOARD: OFFLINE")
		return out
	var line := PackedStringArray()
	for i in mini(RangeBoard.SHOWN, rows.size()):
		var row: Array = rows[i]
		var score: int = type_convert(row[1], TYPE_INT)
		line.append("%d %s %d" % [i + 1, str(row[0]).left(8), score])
		if line.size() == 2 or i == mini(RangeBoard.SHOWN, rows.size()) - 1:
			out.append([("COUNTY " if i < 2 else "       ") + "  ".join(line), HUD.AMBER])
			line = PackedStringArray()
	return out


static func _targets_of(t: Targets, station: String) -> Array:
	var out: Array = []
	for target: Dictionary in t.targets:
		if str(target["station"]) == station:
			out.append(target)
	return out


## The station's target hit last.
static func _latest(t: Targets, station: String) -> Dictionary:
	var best := {}
	var most := 0.0
	for target: Dictionary in _targets_of(t, station):
		var dps: Array = target["dps"]
		if dps.is_empty():
			continue
		var newest: Array = dps[dps.size() - 1]
		var at: float = newest[0]
		if at > most:
			most = at
			best = target
	return best


static func _hit_line(target: Dictionary) -> String:
	var last: Array = target["last"]
	if last.is_empty():
		return ""
	var gun_index: int = last[0]
	var gun := str(Weapons.LABELS[gun_index]).get_slice(" [", 0)
	var dealt: float = last[1]
	var yards: float = last[2]
	if dealt < 0.0:
		return "BLAST AT %d YDS" % roundi(yards)
	return "%s %d A HIT AT %d YDS" % [gun, roundi(dealt), roundi(yards)]


static func _yards(game: Game, target: Dictionary) -> int:
	var tx: float = target["x"]
	var ty: float = target["y"]
	return roundi(Vector2(tx - game.player.x, ty - game.player.y).length())


static func _heat(game: Game) -> Color:
	return HUD.LOW if game.armory.rifle_heat > .6 else READ


## The critters a station turned out: name, health or soak, what they are doing.
static func _critters(f: FiringRange, station: String, soak: bool) -> Array:
	var out: Array = []
	for foe: Enemy in f.watched:
		var w: Dictionary = f.watched[foe]
		if str(w["station"]) != station or not foe.alive:
			continue
		var name := str(L.NAMES.get(foe.kind, foe.kind.to_upper()))
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
