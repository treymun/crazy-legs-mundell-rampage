## The game modes (CLAUDE.md "Modes"): which rules a game plays by and the
## pieces every mode shares. A game's mode lives in its mode feature
## (features/mode_feature.gd, id "mode"); the rules are GameMode objects, one
## per mode (rules_for). The campaign (one player, the game as it always
## was) is the default: nothing here runs for it.
##
##   Modes.setup(game, "coop", 2)            # before the first tick
##   Modes.setup(game, "deathmatch", 2, {"arena": "hickston:boss"})
##   Modes.rules(game).versus()
##
## The command line picks one for the front end: --mode=coop|deathmatch|
## team_deathmatch|bomb|hostage, --players=<1..10> (four at most outside the
## 5v5 modes; the others played by tools/mode_bot.gd from the project folder,
## or in the 5v5 modes by TacticalBot in any build), --arena=<level>[:<boss
## kind>], --level=<chapter>, --frag-limit=<n>, --time-limit=<seconds>,
## --rounds=<rounds to win>.
class_name Modes
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")

const CAMPAIGN := "campaign"
const COOP := "coop"
const DEATHMATCH := "deathmatch"
const TEAM := "team_deathmatch"
## The 5v5 round modes (tactical_mode.gd): search and destroy, hostage rescue.
const BOMB := "bomb"
const HOSTAGE := "hostage"
## COUNTY RUN, the endless survival mode (county_mode.gd): one player.
const COUNTY := "county"
const NAMES := [CAMPAIGN, COOP, DEATHMATCH, TEAM, BOMB, HOSTAGE, COUNTY]
const TACTICAL := [BOMB, HOSTAGE]
## On: the players' flow fields walked in the 5v5 rounds too, as before
## (tools/net_lag.gd old; nothing hunts a player there).
static var flows_in_rounds := false
const MAX_PLAYERS := 10
## The older modes were written and checked for four players at most.
const MAX_FREE_FOR_ALL := 4
## What each player is called on the HUD and their colour (indicator, tint).
const TAGS := ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10"]
const COLORS := [
	Color8(251, 207, 142),
	Color8(120, 196, 255),
	Color8(160, 236, 92),
	Color8(240, 112, 96),
	Color8(220, 160, 250),
	Color8(250, 226, 120),
	Color8(140, 240, 220),
	Color8(250, 150, 200),
	Color8(190, 190, 250),
	Color8(230, 190, 140),
]
## The tint of each player's pictures (the second on is drawn in their colour).
const TINTS := [
	[1.0, 1.0, 1.0],
	[.72, .9, 1.25],
	[.85, 1.2, .75],
	[1.25, .78, .7],
	[1.1, .85, 1.25],
	[1.25, 1.12, .7],
	[.75, 1.2, 1.1],
	[1.25, .82, 1.05],
	[.95, .95, 1.25],
	[1.2, 1.05, .8],
]
## A player's hit on another counts this much of what it does to the county's
## hands (a revolver round 36 -> 18: about six to drop someone).
static var PVP_SCALE: float = ModeData.get_value("versus", "pvp_scale", .5)
## Versus arenas: <level> or <level>:<boss kind> (that boss's arena box).
const ARENAS := [
	"range",
	"hub",
	"hickston:boss",
	"hickston:jerry",
	"fair:rudy",
	"sawmill:foreman",
	"grainyard",
	"holler",
	"salvage",
	"pumpngo",
	"pineacres",
	"landing",
]
## The 5v5 maps (tools/levels/<id>_plan.gd), each built for both round modes.
const SHOWDOWN_MAPS := ["grainyard", "holler", "salvage"]
## TAG TEAM 2V2: search and destroy two a side on its own small maps, one
## bomb site each (tools/levels/pumpngo_plan.gd, pineacres, landing): first to
## 9 of 16 rounds, 1:30 rounds, a shorter buy time.
const TAGTEAM_MAPS := ["pumpngo", "pineacres", "landing"]
static var TAGTEAM_PLAYERS: int = ModeData.get_value("tagteam", "players", 4)
static var TAGTEAM_OPTIONS: Dictionary = {
	"rounds": ModeData.get_value("tagteam", "rounds", 9),
	"round_seconds": ModeData.get_value("tagteam", "round_seconds", 90.0),
	"buy_seconds": ModeData.get_value("tagteam", "buy_seconds", 15.0),
}

static var _made := {}


static func rules_for(name: String) -> GameMode:
	if not _made.has(name):
		var made: GameMode
		match name:
			COOP:
				made = CoopMode.new()
			DEATHMATCH:
				made = DeathmatchMode.new()
			TEAM:
				made = TeamDeathmatchMode.new()
			BOMB:
				made = BombMode.new()
			HOSTAGE:
				made = HostageMode.new()
			COUNTY:
				made = CountyMode.new()
			_:
				made = CampaignMode.new()
		_made[name] = made
	return _made[name]


## A 5v5 round mode played two a side (TAG TEAM 2V2).
static func is_tag_team(game: Game) -> bool:
	return is_tactical(game) and game.players.size() <= TAGTEAM_PLAYERS


## The game's mode feature (null only before its features are attached).
static func feature(game: Game) -> ModeFeature:
	return game.features.get("mode")


## [spread, reach] of a hitscan or pellet shot about to go (weapons.gd):
## weapons.cfg's spread (scope_spread with the scope up, more as heat_spread
## builds) and range, and in the 5v5 modes the rules' say over them
## (shot_tuning; the campaign never asks the rules).
static func shot_spread(game: Game, p: Player, gun: int, how: Dictionary, heat: float) -> Array:
	var spread: Vector2 = how.get("spread", Vector2.ZERO)
	if p.scoped and how.has("scope_spread"):
		spread = how["scope_spread"]
	if how.has("heat_spread"):
		var heat_spread: float = how["heat_spread"]
		spread += Vector2.ONE * heat_spread * heat
	var reach: float = how["range"]
	return shot_tuning(game, p, gun, spread, reach)


static func shot_tuning(game: Game, p: Player, gun: int, spread: Vector2, reach: float) -> Array:
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	if rides != null:
		# Out of a car's window, or riding along: it strays more
		# (features/vehicles.gd aim_scale; 1 on foot).
		spread *= rides.aim_scale(p)
	var st: ModeFeature = game.features.get("mode")
	if st == null or not (TACTICAL.has(String(st.mode)) or String(st.mode) == COUNTY):
		return [spread, reach]
	return rules(game).shot_tuning(game, p, gun, spread, reach)


## The rules of a game under a mode, or null in the campaign (whose play the
## hooks below never touch: each hands back what it was given).
static func _played(game: Game) -> GameMode:
	var st: ModeFeature = game.features.get("mode")
	if st == null or String(st.mode) == CAMPAIGN:
		return null
	return rules_for(String(st.mode))


## The world holds still this tick (COUNTY RUN: a choice on screen).
static func holds(game: Game) -> bool:
	var r := _played(game)
	return r != null and r.holds(game)


static func move_scale(game: Game, p: Player) -> float:
	var r := _played(game)
	return 1.0 if r == null else r.move_scale(game, p)


static func incoming(game: Game, p: Player, amount: float, cause: String) -> float:
	var r := _played(game)
	return amount if r == null else r.incoming(game, p, amount, cause)


static func hit_reach(game: Game, reach: float) -> float:
	var r := _played(game)
	return reach if r == null else r.hit_reach(game, reach)


static func hit_amount(game: Game, e: Enemy, amount: float, d: float) -> float:
	var r := _played(game)
	return amount if r == null else r.hit_amount(game, e, amount, d)


static func hit_after(
	game: Game, e: Enemy, amount: float, d: float, ax: float, ay: float, slope: float
) -> void:
	var r := _played(game)
	if r != null:
		r.hit_after(game, e, amount, d, ax, ay, slope)


static func blast_tuning(game: Game, shot: GameState.Shot, radius: float, strength: float) -> Array:
	var r := _played(game)
	return (
		[radius, strength, 0.0, 0.0] if r == null else r.blast_tuning(game, shot, radius, strength)
	)


static func rules(game: Game) -> GameMode:
	var st := feature(game)
	return rules_for(CAMPAIGN if st == null else String(st.mode))


static func mode_of(game: Game) -> String:
	var st := feature(game)
	return CAMPAIGN if st == null else String(st.mode)


static func is_versus(game: Game) -> bool:
	return rules(game).versus()


## A 5v5 round mode (search and destroy, hostage rescue).
static func is_tactical(game: Game) -> bool:
	return TACTICAL.has(mode_of(game))


static func tag(p: Player) -> String:
	if p.name != "":
		return p.name
	return str(TAGS[p.slot % TAGS.size()])


static func color(p: Player) -> Color:
	return COLORS[p.slot % COLORS.size()]


## Puts `game` (made, never ticked) under mode `name` with `count` players:
## the others join beside player one. options: arena (versus: a boss kind's
## box, from --arena), frag_limit, time_limit. The mode's own start (scaling,
## enemies off, spawn points, kits) runs on the first tick.
## What an online lobby may set on a match (Modes.setup copies each one given
## into the mode feature; features/mode_feature.gd says what each does).
const HOST_SETTINGS := [
	"freeze_seconds",
	"buy_seconds",
	"round_seconds",
	"start_money",
	"friendly_fire",
	"bot_skill",
	"bots",
	"store_rules",
	"teams",
	"names",
]


static func setup(game: Game, name: String, count: int, options := {}) -> void:
	var st := feature(game)
	if st == null or not NAMES.has(name):
		return
	st.mode = name
	st.arena = str(options.get("arena", ""))
	var frag_limit: int = options.get("frag_limit", st.frag_limit)
	st.frag_limit = frag_limit
	var time_limit: float = options.get("time_limit", st.time_limit)
	st.time_limit = time_limit
	var rounds: int = options.get("rounds", st.rounds_to_win)
	st.rounds_to_win = clampi(rounds, 1, 16)
	# An online lobby's match settings (the 5v5 modes read them).
	for key: String in HOST_SETTINGS:
		if options.has(key):
			st.set(key, options[key])
	count = clampi(
		count,
		1,
		(
			MAX_PLAYERS
			if TACTICAL.has(name)
			else CountyCoop.MOST if name == COUNTY else MAX_FREE_FOR_ALL
		)
	)
	while game.players.size() < count:
		join_beside(game, game.players[0])
	for p: Player in game.players:
		p.team = p.slot % 2
		if p.slot < st.names.size() and str(st.names[p.slot]) != "":
			p.name = str(st.names[p.slot])
		rules_for(name).joined(game, st, p)
	if TACTICAL.has(name):
		# The level as built, for each round's start (round_cover.gd).
		RoundCover.remember(game)


## A new player standing beside `anchor`, facing as they do.
static func join_beside(game: Game, anchor: Player) -> Player:
	var at := open_spot_near(game, anchor.x, anchor.y)
	var p := Players.join(game, at.x, at.y, anchor.angle)
	game.focus(game.local_player)
	return p


## Someone joining a running online co-op or (team) deathmatch match: the
## slot of a player whose person left (Player.away) when there is one, else a
## new player (MAX_FREE_FOR_ALL at most; null: no room). Co-op: beside a
## partner up, on their feet with the lead's guns; versus: on the spawn point
## farthest from everyone with the kit (team deathmatch: on the team with
## fewer up). Called between ticks on the host, and on every copy before
## the tick whose row carries it (NetWire.event, NetSync.play_event).
static func join_late(game: Game, name: String) -> Player:
	var st := feature(game)
	if st == null or not (String(st.mode) in [COOP, DEATHMATCH, TEAM]):
		return null
	var p: Player = null
	for q: Player in game.players:
		if q.away:
			p = q
			break
	if p == null:
		if game.players.size() >= MAX_FREE_FOR_ALL:
			return null
		p = join_beside(game, game.players[0])
		rules(game).joined(game, st, p)
	p.away = false
	p.name = name
	p.frags = 0
	p.deaths = 0
	p.downed_by = -1
	if String(st.mode) == COOP:
		var near := Players.nearest(game, game.players[0].x, game.players[0].y)
		if near == null or near == p:
			near = game.players[0]
		carry(near, p)
		var at := open_spot_near(game, near.x, near.y)
		place(game, p, at.x, at.y, near.angle)
		stand_up(game, p, 100)
	else:
		if String(st.mode) == TEAM:
			var up := [0, 0]
			for q: Player in game.players:
				if q != p and not q.away:
					up[q.team % 2] += 1
			p.team = 0 if up[0] <= up[1] else 1
		var spot := far_spawn(game, st, p)
		var sx: float = spot[0]
		var sy: float = spot[1]
		var sa: float = spot[2]
		place(game, p, sx, sy, sa)
		give_kit(p)
		stand_up(game, p, 100)
	game.focus(game.local_player)
	return p


## The person playing `p` left an online co-op or deathmatch match: they lie
## out of play (down, never stood up again, not drawn) until a late joiner
## takes the slot. On the host between ticks, and on every copy before the
## tick whose row carries it (NetWire.event).
static func went_away(game: Game, p: Player) -> void:
	p.away = true
	p.health = 0
	p.down_at = game.clock
	p.revive = 0.0
	p.holding = false
	p.scoped = false


## A partner's own kit into the next game (a chapter after a chapter, a retry
## of one): health (back to full after a game over), guns, rounds, pockets.
static func carry(from: Player, to: Player) -> void:
	to.health = from.health if from.health > 0 else 100
	for i in Weapons.COUNT:
		to.armory.owned[i] = from.armory.owned[i]
		to.armory.loaded[i] = from.armory.loaded[i]
		to.armory.reserve[i] = from.armory.reserve[i]
	to.armory.active = from.armory.active
	to.armory.scrap = from.armory.scrap
	to.armory.mods = from.armory.mods.duplicate()
	if not is_same(from.inventory, to.inventory):
		to.inventory = from.inventory.duplicate()
	to.frags = from.frags
	to.deaths = from.deaths


## Co-op: every partner more than a few steps from player one (a retried boss
## fight puts player one at the door; a save is loaded) comes to their side,
## on their feet.
static func gather(game: Game) -> void:
	var lead: Player = game.players[0]
	for p: Player in game.players:
		if p == lead or p.away:
			continue
		if Vector2(p.x - lead.x, p.y - lead.y).length() > 4.0:
			var at := open_spot_near(game, lead.x, lead.y)
			place(game, p, at.x, at.y, lead.angle)
		if p.health <= 0:
			stand_up(game, p, CoopMode.REVIVE_HEALTH)


## Open floor a body fits on near (x, y), seen from there and clear of every
## player up, or (x, y) itself when there is none.
static func open_spot_near(game: Game, x: float, y: float) -> Vector2:
	var w: LevelData = game.world
	for reach: float in [1.0, 1.5, 2.1, 2.8]:
		for k in 8:
			var a := k * TAU / 8.0 + .3
			var at := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if w.blocked(at.x, at.y, .3) or not w.visible(x, y, at.x, at.y):
				continue
			var clear := true
			for q: Player in game.players:
				if q.health > 0 and Vector2(q.x, q.y).distance_to(at) < .6:
					clear = false
			if clear:
				return at
	return Vector2(x, y)


## Stands `p` at (x, y) facing `angle`, still, eye at the floor's height.
static func place(game: Game, p: Player, x: float, y: float, angle: float) -> void:
	p.x = x
	p.y = y
	p.angle = angle
	p.vx = 0.0
	p.vy = 0.0
	p.air = 0.0
	p.vertical_speed = 0.0
	p.pitch = 0.0
	p.crouched = false
	p.eye = game.world.elevation(x, y) + .95


## Back on their feet with `health`, the down and the revive forgotten.
static func stand_up(game: Game, p: Player, health: int) -> void:
	p.health = health
	p.down_at = -1.0
	p.revive = 0.0
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = game.world.stand(p) + .95


## A notice for this machine's player, whoever is acting.
static func say(game: Game, text: String, seconds := 2.6) -> void:
	game.notice = text
	game.message_until = game.clock + seconds


# ------------------------------------------------------------------ arenas


## The level and the box (Rect2i of cells; an empty one: the whole level) an
## arena name stands for ("hickston:boss" -> hickston, the sheriff's box).
static func arena_of(name: String) -> Array:
	var parts := name.split(":")
	var level_id := parts[0] if parts[0] != "" else "range"
	return [level_id, parts[1] if parts.size() > 1 else ""]


static func arena_box(game: Game, kind: String) -> Rect2i:
	if kind == "":
		return Rect2i()
	var spec: Variant = game.world.boss_arena.get(kind, {})
	var box: Variant = null
	if spec is Dictionary:
		var spec_dict: Dictionary = spec
		box = spec_dict.get("box")
	if not (box is Array):
		return Rect2i()
	var b: Array = box
	if b.size() < 4:
		return Rect2i()
	var x0: int = b[0]
	var y0: int = b[1]
	var x1: int = b[2]
	var y1: int = b[3]
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


## Up to `want` spawn points for versus: open, dry cells with room round them
## (nothing within .45), that walk to one another, inside `box` (the whole
## level when empty), spread out: each next one the farthest from those taken
## (the first nearest the middle). [x, y, facing the middle].
static func spawn_points(game: Game, box: Rect2i, want := 12) -> Array:
	var w: LevelData = game.world
	var area := box if box.size != Vector2i.ZERO else Rect2i(0, 0, w.width, w.height)
	area = area.intersection(Rect2i(0, 0, w.width, w.height))
	var middle := Vector2(area.position) + Vector2(area.size) * .5
	if box.size == Vector2i.ZERO:
		middle = Vector2(float(w.spawn[0]), float(w.spawn[1]))
	# The open cells reached from the open cell nearest the middle.
	var seed := Vector2i(-1, -1)
	var best := INF
	var room := {}
	for cy in range(area.position.y, area.end.y):
		for cx in range(area.position.x, area.end.x):
			var x := cx + .5
			var y := cy + .5
			if w.blocked(x, y, .45):
				continue
			if w.surface_sound(int(w.floor_tile[w.cell(x, y)])) == "water":
				continue
			room[Vector2i(cx, cy)] = true
			var d := Vector2(x, y).distance_squared_to(middle)
			if d < best:
				best = d
				seed = Vector2i(cx, cy)
	if seed.x < 0:
		return []
	var reached := {seed: true}
	var queue: Array[Vector2i] = [seed]
	var head := 0
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := at + n
			if reached.has(next) or not area.has_point(next):
				continue
			if w.blocked(next.x + .5, next.y + .5, .2):
				continue
			reached[next] = true
			queue.append(next)
	var cells: Array = []
	for at: Vector2i in queue:
		if room.has(at):
			cells.append(Vector2(at.x + .5, at.y + .5))
	var out: Array = []
	var taken: Array = []
	if cells.is_empty():
		return out
	taken.append(Vector2(seed.x + .5, seed.y + .5))
	while taken.size() < mini(want, cells.size()):
		var far := -1.0
		var pick := Vector2.ZERO
		for c: Vector2 in cells:
			var near := INF
			for t: Vector2 in taken:
				near = minf(near, c.distance_squared_to(t))
			if near > far:
				far = near
				pick = c
		if far < 4.0:
			break
		taken.append(pick)
	for t: Vector2 in taken:
		out.append([t.x, t.y, atan2(middle.y - t.y, middle.x - t.x)])
	return out


## The spawn point farthest from every other player up (ties: the first).
static func far_spawn(game: Game, st: ModeFeature, p: Player) -> Array:
	var spots: Array = st.spawns
	if spots.is_empty():
		var s: Array = game.level.spawn
		var sx: float = s[0]
		var sy: float = s[1]
		var sa: float = s[2]
		return [sx, sy, sa]
	var best: Array = spots[0]
	var far := -1.0
	for spot: Array in spots:
		var near := INF
		for q: Player in game.players:
			if q != p and q.health > 0:
				var spot_x: float = spot[0]
				var spot_y: float = spot[1]
				near = minf(near, Vector2(q.x, q.y).distance_squared_to(Vector2(spot_x, spot_y)))
		if near > far:
			far = near
			best = spot
	return best


## Every enemy gone (versus): the level's own, its waves and partners.
static func clear_enemies(game: Game) -> void:
	game.enemies.clear()
	game.enemy_ids.clear()
	game.wave.clear()
	game.partners.clear()
	game.boss = null
	game.jerry = null
	game.bessie = null
	game.finale = null
	game.total_kills = 0
	# The boss features' own lists go too: a copy put on a snapshot would find
	# names of bosses no longer in the game (online deathmatch in an arena).
	for key: Array in [
		["boss_fight", "bosses"], ["boss_arena", "bosses"], ["boss_gear", "gear"], ["squad", "busy"]
	]:
		var f: Object = game.features.get(str(key[0]))
		if f != null:
			var listed: Array = f.get(str(key[1]))
			listed.clear()
	for key: Array in [["variants", "tough"], ["boss_arenas", "boss"], ["mothership", "maw"]]:
		var f: Object = game.features.get(str(key[0]))
		if f != null:
			f.set(str(key[1]), null)


## A versus starting kit: the crowbar, the .38 and the shotgun with rounds.
static func give_kit(p: Player) -> void:
	var a: Weapons.Armory = p.armory
	for i in Weapons.COUNT:
		a.owned[i] = i == Weapons.CROWBAR or i == Weapons.REVOLVER or i == Weapons.SHOTGUN
		a.loaded[i] = 0
		a.reserve[i] = 0
	a.loaded[Weapons.REVOLVER] = Weapons.CAPACITY[Weapons.REVOLVER]
	a.reserve[Weapons.REVOLVER] = 30
	a.loaded[Weapons.SHOTGUN] = Weapons.CAPACITY[Weapons.SHOTGUN]
	a.reserve[Weapons.SHOTGUN] = 12
	a.active = Weapons.SHOTGUN
	a.reload = 0.0
	a.cooldown = 0.0
	a.fuse = 0.0
	a.tnt_latched = false
	a.switch = 0.0


# ------------------------------------------------------------- player hits


## The nearest player (not the acting one, up, one a hit of theirs can land
## on) along the acting player's shot, nearer than `near`: [player, distance]
## or [] (game_combat.gd hitscan, when the mode lets bullets hit players).
static func player_in_line(
	game: Game, ax: float, ay: float, slope: float, spread: float, near: float
) -> Array:
	var me: Player = game.player
	var r := rules(game)
	var out: Array = []
	for q: Player in game.players:
		if q == me or q.health <= 0 or r.hurt_scale(game, me, q, false) <= 0.0:
			continue
		var dx := q.x - me.x
		var dy := q.y - me.y
		var d := dx * ax + dy * ay
		var z := me.eye + d * slope
		var feet: float = game.world.stand(q) + q.air
		var top := feet + (.8 if q.crouched else 1.08)
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < GameState.PLAYER_RADIUS + .07 + spread
			and feet - .05 < z
			and z < top
			and game.world.visible(me.x, me.y, q.x, q.y, me.eye, z)
		):
			near = d
			out = [q, d, (z - feet) / (top - feet)]
	return out


## The acting player's hit of `amount` (as it would hurt a hand) lands on
## `victim`: the mode's damage (GameMode.pvp_damage: PVP_SCALE and friendly
## fire; the 5v5 modes their own table, head and armour), blamed on the
## shooter (frags), with blood and the crosshair's mark. `height` is where on
## the body it struck (0 the feet, 1 the top of the head; -1 not known).
static func player_hit(
	game: Game, victim: Player, amount: float, cause := "SHOT", height := -1.0
) -> void:
	var me: Player = game.player
	if victim.health <= 0:
		return
	var dealt := rules(game).pvp_damage(game, me, victim, amount, game.armory.active, height)
	if dealt <= 0.0:
		return
	_blamed(game, me.slot, victim, dealt, [me.x, me.y], cause)
	game.burst(victim.x, victim.y, victim.eye - .3, "gore", 6, 1.2)
	game.struck(dealt, victim.health <= 0, false)


## A blast's bite on player `p` (game_combat.gd explode): a player's own blast
## or a partner's as the mode says, blamed on its thrower; anything else (an
## enemy's, a fuel drum's) in full, as always.
static func blast_hit(
	game: Game, shot: GameState.Shot, p: Player, amount: int, cause: String
) -> void:
	var st := feature(game)
	var thrown: bool = not shot.enemy and shot.kind != "fuel" and shot.owner != -1
	if st == null or String(st.mode) == CAMPAIGN or not thrown or shot.slot >= game.players.size():
		game.damage(amount, [shot.x, shot.y], cause, p)
		return
	var thrower: Player = game.players[shot.slot]
	var dealt := rules(game).blast_damage(game, thrower, p, float(amount), String(shot.kind))
	if dealt <= 0.0:
		return
	_blamed(
		game, shot.slot, p, maxf(1.0, dealt), [shot.x, shot.y], cause if thrower == p else "BLAST"
	)


## A player's shot in flight striking another player's body (game_combat.gd
## _hits, when the mode lets bullets hit players): true when it did (the shot
## is finished there; one that blows up does).
static func shot_strikes(game: Game, shot: GameState.Shot, x: float, y: float, z: float) -> bool:
	if not rules(game).bullets_hit_players() or shot.slot >= game.players.size():
		return false
	var thrower: Player = game.players[shot.slot]
	for q: Player in game.players:
		if q == thrower or q.health <= 0:
			continue
		var feet: float = game.world.stand(q) + q.air
		if (
			Vector2(q.x - x, q.y - y).length() < GameState.PLAYER_RADIUS + .1
			and feet - .05 < z
			and z < feet + 1.08
		):
			var dealt := 0.0
			if shot.damage > 0:
				dealt = (rules(game).pvp_damage(
					game,
					thrower,
					q,
					float(shot.damage),
					shot_weapon(String(shot.kind)),
					(z - feet) / 1.08
				))
			if dealt > 0.0:
				_blamed(game, shot.slot, q, dealt, [x, y], "SHOT")
				game.burst(q.x, q.y, z, "gore", 6, 1.2)
			game.finish_shot(shot)
			return true
	return false


## The gun a player's shot in flight came from, by the shot's kind (-1: none).
static func shot_weapon(kind: String) -> int:
	match kind:
		"bolt":
			return Weapons.CROSSBOW
		"blade":
			return Weapons.RIPSAW
		"arm_bolt":
			return Weapons.ARMGUN
		"bottle_rocket":
			return Weapons.ROCKET
		"bowling":
			return Weapons.BOWLING
		"keg":
			return Weapons.KEG
		"cow":
			return Weapons.COW
		"tnt":
			return Weapons.DYNAMITE
	return -1


static func _blamed(
	game: Game, slot: int, victim: Player, amount: float, at: Array, cause: String
) -> void:
	var st := feature(game)
	if st != null:
		st.blame = slot
	game.damage(amount, at, cause, victim)
	if st != null:
		st.blame = -1
