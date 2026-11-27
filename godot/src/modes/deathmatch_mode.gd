## Deathmatch: every player for themselves in an arena (CLAUDE.md "Modes").
##
## No enemies (the level's own, its posse and critters are cleared at the
## start). Players start on the map's own deathmatch starts when it names
## them (LevelData.tactical "deathmatch", a map source's dm_spawn objects,
## pass 16), else on spawn points worked out from the arena
## (Modes.spawn_points: open dry ground with room round it, spread out) with
## the starting kit (Modes.give_kit: crowbar, .38, shotgun). Every hit lands
## (PVP_SCALE of what it does to a hand; your own blast hurts you too). A
## kill of another player is a frag; a death to your own blast or the world
## takes one away. A player down comes back RESPAWN_DELAY seconds later on the
## spawn point farthest from everyone up, with full health and the kit again.
## Pickups lying about come back PICKUP_BACK seconds after they are taken
## (keys and quest items never). The match ends at the frag limit or the time
## limit (st.frag_limit, st.time_limit) with the results screen.
class_name DeathmatchMode
extends GameMode

static var RESPAWN_DELAY: float = ModeData.get_value("deathmatch", "respawn_delay", 3.0)
static var PICKUP_BACK: float = ModeData.get_value("deathmatch", "pickup_back", 20.0)
static var FRAG_LIMIT: int = ModeData.get_value("deathmatch", "frag_limit", 10)
static var TIME_LIMIT: float = ModeData.get_value("deathmatch", "time_limit", 300.0)


func id() -> String:
	return Modes.DEATHMATCH


func versus() -> bool:
	return true


func bullets_hit_players() -> bool:
	return true


func hurt_scale(_game: Game, _attacker: Player, _victim: Player, _blast: bool) -> float:
	return 1.0


func start(game: Game, st: ModeFeature) -> void:
	Modes.clear_enemies(game)
	var kind := str(Modes.arena_of(st.arena)[1])
	var named: Variant = game.world.tactical.get("deathmatch", [])
	var own: Array = named if named is Array else []
	if not own.is_empty() and kind == "":
		st.spawns = own.duplicate(true)
	else:
		st.spawns = Modes.spawn_points(game, Modes.arena_box(game, kind), 12)
	st.pickup_spots = []
	for entry: Array in game.pickups:
		var name := str(entry[0])
		if not name.begins_with("key_") and not GameState.TASK_ITEMS.has(name):
			var ex: float = entry[1]
			var ey: float = entry[2]
			st.pickup_spots.append([name, ex, ey])
	st.pickups_back = []
	var spots: Array = st.spawns
	for p: Player in game.players:
		var spot: Array = (
			spots[p.slot % spots.size()] if not spots.is_empty() else Modes.far_spawn(game, st, p)
		)
		var sx: float = spot[0]
		var sy: float = spot[1]
		var sa: float = spot[2]
		Modes.place(game, p, sx, sy, sa)
		Modes.give_kit(p)
		p.health = 100
		p.frags = 0
		p.deaths = 0
	game.spawn_grace = 0.0
	Modes.say(game, "%s: FIRST TO %d FRAGS." % [title(), st.frag_limit], 3.0)


func title() -> String:
	return "DEATHMATCH"


func tick(game: Game, st: ModeFeature, _dt: float) -> void:
	if st.match_over:
		return
	for p: Player in game.players:
		if p.health > 0 or p.away:
			continue
		if p.down_at < 0.0:
			p.down_at = game.clock
		if game.clock - p.down_at >= RESPAWN_DELAY:
			respawn(game, st, p)
	_pickups_back(game, st)
	if leader_score(game) >= st.frag_limit or game.clock >= st.time_limit:
		st.match_over = true
		st.over_clock = game.clock
		game.won = true


## Taken pickups come back where they lay.
func _pickups_back(game: Game, st: ModeFeature) -> void:
	var waiting: Array = st.pickups_back
	for spot: Array in st.pickup_spots:
		var sx: float = spot[1]
		var sy: float = spot[2]
		var lying := false
		for entry: Array in game.pickups:
			var ex: float = entry[1]
			var ey: float = entry[2]
			if str(entry[0]) == str(spot[0]) and absf(ex - sx) < .01 and absf(ey - sy) < .01:
				lying = true
				break
		var queued := -1
		for k in waiting.size():
			var w: Array = waiting[k]
			var wx: float = w[1]
			var wy: float = w[2]
			if absf(wx - sx) < .01 and absf(wy - sy) < .01:
				queued = k
		if lying or queued >= 0:
			if queued >= 0:
				var back_at: float = waiting[queued][3]
				if game.clock >= back_at:
					game.add_pickup(str(spot[0]), sx, sy)
					waiting.remove_at(queued)
			continue
		waiting.append([spot[0], spot[1], spot[2], game.clock + PICKUP_BACK])


func downed(game: Game, _st: ModeFeature, p: Player, by: int) -> void:
	p.deaths += 1
	if by >= 0 and by != p.slot and by < game.players.size():
		var killer: Player = game.players[by]
		killer.frags += 1
		if killer == game.local_player:
			Modes.say(game, "YOU FRAGGED %s." % Modes.tag(p))
		elif p != game.local_player:
			Modes.say(game, "%s FRAGGED %s." % [Modes.tag(killer), Modes.tag(p)])
	else:
		p.frags -= 1
		if p != game.local_player:
			Modes.say(game, "%s CASHED OUT." % Modes.tag(p))


func respawn(game: Game, st: ModeFeature, p: Player) -> void:
	var spot := Modes.far_spawn(game, st, p)
	var sx: float = spot[0]
	var sy: float = spot[1]
	var sa: float = spot[2]
	Modes.place(game, p, sx, sy, sa)
	Modes.give_kit(p)
	Modes.stand_up(game, p, 100)
	p.downed_by = -1


## Versus is never lost: a match ends on its limits (over()).
func defeated(_game: Game, _st: ModeFeature) -> bool:
	return false


func over(_game: Game, st: ModeFeature) -> bool:
	return st.match_over


## The best score (frags here; a team's in team deathmatch).
func leader_score(game: Game) -> int:
	var best := -999
	for p: Player in game.players:
		best = maxi(best, p.frags)
	return best


## [label, frags, deaths] per player, the most frags first (ties: fewer
## deaths, then the lower slot).
func scores(game: Game, _st: ModeFeature) -> Array:
	var order: Array = game.players.duplicate()
	order.sort_custom(
		func(a: Player, b: Player) -> bool:
			if a.frags != b.frags:
				return a.frags > b.frags
			if a.deaths != b.deaths:
				return a.deaths < b.deaths
			return a.slot < b.slot
	)
	var rows: Array = []
	for p: Player in order:
		rows.append([Modes.tag(p), p.frags, p.deaths, p.slot])
	return rows


## Who won, for the ribbon: "P1", "RED", or "TIE".
func winner(game: Game) -> String:
	var rows := scores(game, null)
	if rows.size() > 1:
		var first: int = rows[0][1]
		var second: int = rows[1][1]
		if first == second:
			return "TIE"
	return str(rows[0][0]) if not rows.is_empty() else "TIE"
