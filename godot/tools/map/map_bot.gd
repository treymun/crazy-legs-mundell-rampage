## The bot run of one map (map check's step 5 and `map flow`): the balance
## bot (tools/balance_pilot.gd) plays the level as built (in memory: a
## LevelData.preview) with god mode off, NORMAL by default, from the start kit
## (data/tuning/map_review.json "kit", a source's meta.kit merged over it),
## each attempt recorded by tools/flow_probe.gd as tools/flow_report.gd
## records a chapter's. A death starts the map again (a fresh game, the next
## attempt's dice), up to `tries`; the campaign runs are untouched.
extends RefCounted

const Pilot := preload("res://tools/balance_pilot.gd")
const Probe := preload("res://tools/flow_probe.gd")
const STEP := 1.0 / 60.0


## The balance bot, but one that gives up on a hand it has not hurt in
## GIVE_UP seconds of shooting (a hand up on a loft it cannot hit from below,
## behind a rail or a deck's edge) and goes on along the way for IGNORE
## seconds, as a player would go round and up. The campaign's bot is as it
## was; the hand is hidden from its pick only during the pick, so play is
## untouched.
class MapPilot:
	extends Pilot

	const GIVE_UP := 5.0
	const IGNORE := 12.0

	var _aim_at := -1
	var _aim_hp := 0.0
	var _aim_since := 0.0
	var _ignored := {}

	func _init(level := 1, seed_value := 1) -> void:
		super(level, seed_value)

	func steer(game: Game) -> Game.Controls:
		var hidden: Array = []
		for e: Enemy in game.enemies:
			if float(_ignored.get(e.uid, -1.0)) > game.clock and (e.alerted or e.player_seen):
				hidden.append([e, e.alerted, e.player_seen])
				e.alerted = false
				e.player_seen = false
		var c := super.steer(game)
		for row: Array in hidden:
			var e: Enemy = row[0]
			e.alerted = row[1]
			e.player_seen = row[2]
		if foe == null:
			_aim_at = -1
		elif foe.uid != _aim_at or foe.hp < _aim_hp - .01:
			_aim_at = foe.uid
			_aim_hp = foe.hp
			_aim_since = game.clock
		elif game.clock - _aim_since > GIVE_UP:
			_ignored[foe.uid] = game.clock + IGNORE
			_aim_at = -1
		return c


## The options a bot game plays with (as flow_report.gd's, BLUE and the
## bench and openers off: a map is judged on its own).
static func options(diff: int) -> Dictionary:
	var o: Dictionary = SessionStore.defaults().duplicate()
	o["difficulty"] = diff
	o["hound"] = 0
	o["bench"] = 0
	o["opener"] = 0
	o["openers"] = 0
	return o


## The kit into a fresh game: gun name -> rounds (owned, its pool filled),
## pocket item -> count.
static func give(g: Game, kit: Dictionary) -> void:
	for key: String in kit:
		var amount := int(kit[key])
		var slot := Weapons.NAMES.find(key)
		if slot >= 0:
			g.armory.owned[slot] = true
			g.armory.reserve[slot] = maxi(g.armory.reserve[slot], amount)
			if slot < Weapons.CAPACITY.size():
				g.armory.loaded[slot] = Weapons.CAPACITY[slot]
		elif HUD.ITEMS.has(key):
			g.inventory[key] = amount


## Plays map_id (LevelData.preview must hold it, or data/<id>.json) until a
## clear or `tries` attempts: {outcome, secs (the clearing or last attempt's),
## deaths, kills, attempts: [the probe's rows], flow (the last attempt's),
## at: [x, y] where it ended, skill, seed}.
static func play(
	main, map_id: String, kit: Dictionary, skill: int, seed_value: int, opts: Dictionary
) -> Dictionary:
	var limit := float(opts.get("seconds", 420.0))
	var tries := int(opts.get("tries", 4))
	var o := options(int(opts.get("diff", 1)))
	for key: String in o:
		main.options[key] = o[key]
	var rows: Array = []
	var deaths := 0
	var outcome := "timeout"
	var last := {}
	for attempt in range(1, tries + 1):
		var g: Game = main.make_game(map_id)
		g.configure(main.options)
		g.lessons = false
		give(g, kit)
		g.rng = GameState.Rng.new(seed_value * 1009 + attempt)
		var pilot := MapPilot.new(skill, seed_value * 13 + attempt)
		var probe := Probe.new(g, pilot)
		var start := g.clock
		outcome = "timeout"
		while g.clock - start < limit:
			probe.before()
			var c := pilot.steer(g)
			g.tick(STEP, c)
			pilot.moved(g)
			probe.after()
			if g.won:
				outcome = "clear"
				break
			if g.player.health <= 0:
				outcome = "death"
				break
		var row := {"attempt": attempt}
		probe.finish(row, outcome)
		rows.append(row)
		last = row
		if outcome != "death":
			break
		deaths += 1
	var kills := 0
	for r: Dictionary in rows:
		kills += int(r.get("kills", 0))
	return {
		"outcome": outcome,
		"secs": last.get("secs", 0.0),
		"deaths": deaths,
		"kills": kills,
		"attempts": rows,
		"flow": last.get("flow", {}),
		"fights": last.get("fights", []),
		"at": [last.get("x", 0.0), last.get("y", 0.0)],
		"skill": Pilot.SKILLS[clampi(skill, 0, 2)]["name"],
		"seed": seed_value,
	}
