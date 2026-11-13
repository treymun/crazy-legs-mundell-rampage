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

const CAMPAIGN := "campaign"
const COOP := "coop"
const DEATHMATCH := "deathmatch"
const TEAM := "team_deathmatch"
## The 5v5 round modes (tactical_mode.gd): search and destroy, hostage rescue.
const BOMB := "bomb"
const HOSTAGE := "hostage"
const NAMES := [CAMPAIGN, COOP, DEATHMATCH, TEAM, BOMB, HOSTAGE]
const TACTICAL := [BOMB, HOSTAGE]
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
const PVP_SCALE := .5
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
]
## The 5v5 maps (tools/levels/<id>_plan.gd), each built for both round modes.
const SHOWDOWN_MAPS := ["grainyard", "holler", "salvage"]

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
			_:
				made = CampaignMode.new()
		_made[name] = made
	return _made[name]


## The game's mode feature (null only before its features are attached).
static func feature(game):
	return game.features.get("mode")


static func rules(game) -> GameMode:
	var st = feature(game)
	return rules_for(CAMPAIGN if st == null else String(st.mode))


static func mode_of(game) -> String:
	var st = feature(game)
	return CAMPAIGN if st == null else String(st.mode)


static func is_versus(game) -> bool:
	return rules(game).versus()


## A 5v5 round mode (search and destroy, hostage rescue).
static func is_tactical(game) -> bool:
	return TACTICAL.has(mode_of(game))


static func tag(p: Player) -> String:
	return String(TAGS[p.slot % TAGS.size()])


static func color(p: Player) -> Color:
	return COLORS[p.slot % COLORS.size()]


## Puts `game` (made, never ticked) under mode `name` with `count` players:
## the others join beside player one. options: arena (versus: a boss kind's
## box, from --arena), frag_limit, time_limit. The mode's own start (scaling,
## enemies off, spawn points, kits) runs on the first tick.
static func setup(game, name: String, count: int, options := {}) -> void:
	var st = feature(game)
	if st == null or not NAMES.has(name):
		return
	st.mode = name
	st.arena = String(options.get("arena", ""))
	st.frag_limit = int(options.get("frag_limit", st.frag_limit))
	st.time_limit = float(options.get("time_limit", st.time_limit))
	st.rounds_to_win = clampi(int(options.get("rounds", st.rounds_to_win)), 1, 16)
	count = clampi(count, 1, MAX_PLAYERS if TACTICAL.has(name) else MAX_FREE_FOR_ALL)
	while game.players.size() < count:
		join_beside(game, game.players[0])
	for p: Player in game.players:
		p.team = p.slot % 2
		rules_for(name).joined(game, st, p)


## A new player standing beside `anchor`, facing as they do.
static func join_beside(game, anchor: Player) -> Player:
	var at := open_spot_near(game, anchor.x, anchor.y)
	var p := Players.join(game, at.x, at.y, anchor.angle)
	game.focus(game.local_player)
	return p


## A partner's own kit into the next game (a chapter after a chapter, a retry
## of one): health (back to full after a game over), guns, rounds, pockets.
static func carry(from: Player, to: Player) -> void:
	to.health = from.health if from.health > 0 else 100
	for i in Weapons.COUNT:
		to.armory.owned[i] = from.armory.owned[i]
		to.armory.loaded[i] = from.armory.loaded[i]
		to.armory.reserve[i] = from.armory.reserve[i]
	to.armory.active = from.armory.active
	if not is_same(from.inventory, to.inventory):
		to.inventory = from.inventory.duplicate()
	to.frags = from.frags
	to.deaths = from.deaths


## Co-op: every partner more than a few steps from player one (a retried boss
## fight puts player one at the door; a save is loaded) comes to their side,
## on their feet.
static func gather(game) -> void:
	var lead: Player = game.players[0]
	for p: Player in game.players:
		if p == lead:
			continue
		if Vector2(p.x - lead.x, p.y - lead.y).length() > 4.0:
			var at := open_spot_near(game, lead.x, lead.y)
			place(game, p, at.x, at.y, lead.angle)
		if p.health <= 0:
			stand_up(game, p, CoopMode.REVIVE_HEALTH)


## Open floor a body fits on near (x, y), seen from there and clear of every
## player up, or (x, y) itself when there is none.
static func open_spot_near(game, x: float, y: float) -> Vector2:
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
static func place(game, p: Player, x: float, y: float, angle: float) -> void:
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
static func stand_up(game, p: Player, health: int) -> void:
	p.health = health
	p.down_at = -1.0
	p.revive = 0.0
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = game.world.elevation(p.x, p.y) + .95


## A notice for this machine's player, whoever is acting.
static func say(game, text: String, seconds := 2.6) -> void:
	game.notice = text
	game.message_until = game.clock + seconds


# ------------------------------------------------------------------ arenas


## The level and the box (Rect2i of cells; an empty one: the whole level) an
## arena name stands for ("hickston:boss" -> hickston, the sheriff's box).
static func arena_of(name: String) -> Array:
	var parts := name.split(":")
	var level_id := parts[0] if parts[0] != "" else "range"
	return [level_id, parts[1] if parts.size() > 1 else ""]


static func arena_box(game, kind: String) -> Rect2i:
	if kind == "":
		return Rect2i()
	var spec = game.world.boss_arena.get(kind, {})
	var box = spec.get("box") if spec is Dictionary else null
	if not (box is Array) or box.size() < 4:
		return Rect2i()
	return Rect2i(int(box[0]), int(box[1]), int(box[2]) - int(box[0]), int(box[3]) - int(box[1]))


## Up to `want` spawn points for versus: open, dry cells with room round them
## (nothing within .45), that walk to one another, inside `box` (the whole
## level when empty), spread out: each next one the farthest from those taken
## (the first nearest the middle). [x, y, facing the middle].
static func spawn_points(game, box: Rect2i, want := 12) -> Array:
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
static func far_spawn(game, st, p: Player) -> Array:
	var spots: Array = st.spawns
	if spots.is_empty():
		var s: Array = game.level.spawn
		return [float(s[0]), float(s[1]), float(s[2])]
	var best: Array = spots[0]
	var far := -1.0
	for spot: Array in spots:
		var near := INF
		for q: Player in game.players:
			if q != p and q.health > 0:
				near = minf(near, Vector2(q.x, q.y).distance_squared_to(Vector2(spot[0], spot[1])))
		if near > far:
			far = near
			best = spot
	return best


## Every enemy gone (versus): the level's own, its waves and partners.
static func clear_enemies(game) -> void:
	game.enemies.clear()
	game.enemy_ids.clear()
	game.wave.clear()
	game.partners.clear()
	game.boss = null
	game.jerry = null
	game.bessie = null
	game.finale = null
	game.total_kills = 0


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
static func player_in_line(game, ax: float, ay: float, slope: float, spread: float, near: float):
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
		var feet: float = game.world.elevation(q.x, q.y) + q.air
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
	game, victim: Player, amount: float, cause := "SHOT", height := -1.0
) -> void:
	var me: Player = game.player
	if victim.health <= 0:
		return
	var dealt := rules(game).pvp_damage(game, me, victim, amount, game.armory.active, height)
	if dealt <= 0.0:
		return
	_blamed(game, me.slot, victim, dealt, [me.x, me.y], cause)
	game.burst(victim.x, victim.y, victim.eye - .3, "blood", 6, 1.2)
	game.struck(dealt, victim.health <= 0, false)


## A blast's bite on player `p` (game_combat.gd explode): a player's own blast
## or a partner's as the mode says, blamed on its thrower; anything else (an
## enemy's, a fuel drum's) in full, as always.
static func blast_hit(game, shot, p: Player, amount: int, cause: String) -> void:
	var st = feature(game)
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
static func shot_strikes(game, shot, x: float, y: float, z: float) -> bool:
	if not rules(game).bullets_hit_players() or shot.slot >= game.players.size():
		return false
	var thrower: Player = game.players[shot.slot]
	for q: Player in game.players:
		if q == thrower or q.health <= 0:
			continue
		var feet: float = game.world.elevation(q.x, q.y) + q.air
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
				game.burst(q.x, q.y, z, "blood", 6, 1.2)
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
	game, slot: int, victim: Player, amount: float, at: Array, cause: String
) -> void:
	var st = feature(game)
	if st != null:
		st.blame = slot
	game.damage(amount, at, cause, victim)
	if st != null:
		st.blame = -1
