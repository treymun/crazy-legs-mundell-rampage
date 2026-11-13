## The game's mode (src/modes/, CLAUDE.md "Modes"): which rules it plays by
## and what they remember that is not on a player. Every game has it; in the
## campaign (the default) it does nothing at all and saves nothing.
##
## It runs the rules' hooks: start on the first tick (after the posse joins),
## tick each tick, downed when a player's health reaches 0 (blamed on `blame`,
## the slot of the player whose hit is landing, -1 the world or an enemy),
## pickup when a player takes something, won when the level is won. A save
## keeps the mode, its numbers and every player past the first (place,
## health, guns, pockets; frags for all), so a co-op save loads as co-op with
## its partners; a snapshot carries all of it (a simulation feature).
extends GameFeature

var mode := Modes.CAMPAIGN
var started := false
## How many of game.enemies have had their health scaled for the party (co-op).
var scaled_upto := 0
## The slot of the player whose hit is landing this moment (Modes._blamed).
var blame := -1
## Versus: the frag limit, the time limit (seconds of play), the arena
## ("range", "hickston:boss"...), its spawn points [x, y, angle], the pickups
## that come back and those on their way back [name, x, y, at].
var frag_limit := DeathmatchMode.FRAG_LIMIT
var time_limit := DeathmatchMode.TIME_LIMIT
var arena := ""
var spawns: Array = []
var pickup_spots: Array = []
var pickups_back: Array = []
var match_over := false
var over_clock := -1.0
## Co-op: partners stood up by a partner this chapter (a tally row).
var revives := 0


func id() -> String:
	return "mode"


func attach() -> void:
	game.ticked.connect(_tick)
	game.player_hurt.connect(_hurt)
	game.pickup_taken.connect(_picked)
	game.level_won.connect(_won)


func rules() -> GameMode:
	return Modes.rules_for(mode)


func defeated() -> bool:
	return rules().defeated(game, self)


func _tick(dt: float) -> void:
	if mode == Modes.CAMPAIGN:
		return
	if not started:
		started = true
		rules().start(game, self)
	rules().tick(game, self, dt)


func _hurt(_amount: float, _cause: String) -> void:
	if mode == Modes.CAMPAIGN:
		return
	var p: Player = game.player
	if p.health > 0 or p.down_at >= 0.0:
		return
	p.down_at = game.clock
	p.revive = 0.0
	p.downed_by = blame
	rules().downed(game, self, p, blame)


func _picked(name: String) -> void:
	if mode != Modes.CAMPAIGN:
		rules().pickup(game, self, name)


func _won() -> void:
	if mode != Modes.CAMPAIGN:
		rules().won(game, self)


func save() -> Dictionary:
	if mode == Modes.CAMPAIGN:
		return {}
	var rows: Array = []
	for p: Player in game.players:
		var row := {"frags": p.frags, "deaths": p.deaths, "team": p.team}
		if p.slot > 0:
			(
				row
				. merge(
					{
						"x": p.x,
						"y": p.y,
						"angle": p.angle,
						"health": p.health,
						"owned": p.armory.owned.duplicate(),
						"loaded": p.armory.loaded.duplicate(),
						"reserve": p.armory.reserve.duplicate(),
						"active": p.armory.active,
						"inventory": p.inventory.duplicate(),
					}
				)
			)
		rows.append(row)
	return {
		"mode": mode,
		"started": started,
		"scaled_upto": scaled_upto,
		"frag_limit": frag_limit,
		"time_limit": time_limit,
		"arena": arena,
		"revives": revives,
		"players": rows,
	}


func restore(state: Dictionary) -> void:
	if not Modes.NAMES.has(String(state.get("mode", ""))):
		return
	mode = String(state["mode"])
	started = bool(state.get("started", false))
	scaled_upto = int(state.get("scaled_upto", 0))
	frag_limit = int(state.get("frag_limit", frag_limit))
	time_limit = float(state.get("time_limit", time_limit))
	arena = String(state.get("arena", ""))
	revives = int(state.get("revives", 0))
	var rows: Array = state.get("players", []) if state.get("players") is Array else []
	for i in mini(rows.size(), Modes.MAX_PLAYERS):
		var row = rows[i]
		if not row is Dictionary:
			continue
		if i >= game.players.size():
			var x := float(row.get("x", game.players[0].x))
			var y := float(row.get("y", game.players[0].y))
			if not SessionStore._valid_position(game.world, x, y):
				var at := Modes.open_spot_near(game, game.players[0].x, game.players[0].y)
				x = at.x
				y = at.y
			Players.join(game, x, y, float(row.get("angle", 0.0)))
			game.focus(game.local_player)
		var p: Player = game.players[i]
		p.frags = int(row.get("frags", 0))
		p.deaths = int(row.get("deaths", 0))
		p.team = int(row.get("team", p.slot % 2))
		if i > 0:
			_kit(p, row)
	if mode == Modes.COOP:
		CoopMode.rescale_loaded(game, self, game.players.size())


## A partner's health, guns and pockets from their row of a save.
func _kit(p: Player, row: Dictionary) -> void:
	p.health = clampi(int(row.get("health", 100)), 0, 100)
	var owned: Array = row.get("owned", [])
	var loaded: Array = row.get("loaded", [])
	var reserve: Array = row.get("reserve", [])
	for k in mini(Weapons.COUNT, mini(owned.size(), mini(loaded.size(), reserve.size()))):
		p.armory.owned[k] = bool(owned[k])
		p.armory.loaded[k] = clampi(int(loaded[k]), 0, Weapons.CAPACITY[k])
		p.armory.reserve[k] = clampi(int(reserve[k]), 0, Weapons.MAX_RESERVE[k])
	var active := int(row.get("active", p.armory.active))
	if active >= 0 and active < Weapons.COUNT and p.armory.owned[active]:
		p.armory.active = active
	var pockets = row.get("inventory", {})
	if pockets is Dictionary:
		for item in HUD.ITEMS:
			p.inventory[item] = clampi(int(pockets.get(item, p.inventory.get(item, 0))), 0, 5)


func sprites() -> Array:
	if game.players.size() < 2:
		return []
	return ModeScreens.sprites(game)


func draw_view(c: Canvas) -> void:
	if game.players.size() < 2:
		return
	ModeScreens.draw_view(c, game, self)


func tally_rows() -> Array:
	if mode == Modes.COOP:
		return [["PARTNERS REVIVED", "%d" % revives]]
	return []
