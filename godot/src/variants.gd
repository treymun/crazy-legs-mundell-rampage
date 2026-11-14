## The county's tougher hands and each chapter's tough guy: enemies.cfg
## sections with a `brain` and the keys below. features/variants_feature.gd
## swaps them in for some of a level's own regulars when a chapter starts
## (by difficulty and the enemy's place in the level, no dice), keeps the
## shield deputies' car doors and names a tough guy when he first sees you.
##
##   art          draw it with this kind's pictures until its own are packed
##                (<kind>_0 in the art index): its own then take over
##   tint         [r, g, b] its pictures are multiplied by (a tough guy)
##   swap         the regular it stands in for
##   steady       the share of a gun's shove and stun it takes (1: all)
##   barrels, blast, fan, delay   a billy or coot brain's shot: how many
##                barrels a pull, each one's [damage close, far], how wide
##                its aim reaches and the wait after
##   aim, wild    its chance to hit times `aim`; its aim thrown off by up to
##                `wild` radians
##   stumbles     how far it weaves as it walks, radians
##   throws       every this many attacks it lobs its jug instead (glass)
##   door         hit points of the car door it holds in front: a shot from
##                the front strikes the door, a blast tears at it; it swings
##                the door aside to fire (door_picture: the door drawn in
##                front of it, "" once its own art carries one)
##   tough_for, tough_title, tough_line   the chapter whose tough guy it is,
##                his name on the HUD and the line under it
class_name Variants
extends RefCounted

## Every how-many-th of a level's regulars of a kind with a variant becomes
## it, by difficulty: EASY none, NORMAL one in nine, HARD one in five, HOG
## WILD one in three.
const EVERY := [0, 9, 5, 3]
## How far round from its front (radians either side) a shot meets the door,
## and how much of a stopped shot gets through it.
const DOOR_ARC := 1.15
const DOOR_LEAK := .08
const DOOR_PICTURE := "made_car_door"
const DOOR_W := 30
const DOOR_H := 34

## Read from Enemy.DEFS by tables() (each load of enemies.cfg).
static var VARIANT_OF := {}
static var TOUGH := {}
static var STUMBLE := {}
static var STEADY := {}
static var DOORS := {}
static var TINTS := {}
## The pictures each kind is drawn with, worked out the first time it is drawn.
static var _stems := {}
## The game's pictures, for the tints (the variants feature sets it).
static var art: Assets = null


static func tables() -> void:
	VARIANT_OF = {}
	TOUGH = {}
	STUMBLE = {}
	STEADY = {}
	DOORS = {}
	TINTS = {}
	_stems = {}
	for kind: String in Enemy.DEFS:
		var d: Dictionary = Enemy.DEFS[kind]
		if d.has("tough_for"):
			TOUGH[String(d["tough_for"])] = kind
		elif d.has("swap"):
			VARIANT_OF[String(d["swap"])] = kind
		if d.has("stumbles"):
			STUMBLE[kind] = float(d["stumbles"])
		if d.has("steady"):
			STEADY[kind] = float(d["steady"])
		if d.has("door"):
			DOORS[kind] = float(d["door"])
		if d.has("tint"):
			TINTS[kind] = d["tint"]


## The kind whose pictures `kind` wears: its own once they are packed.
static func stem(kind: String) -> String:
	var s = _stems.get(kind)
	if s == null:
		s = kind
		var fallback := String(Enemy.DEFS[kind].get("art", ""))
		if fallback != "" and not Assets.shared_index.has(kind + "_0"):
			s = fallback
		if not Assets.shared_index.is_empty():
			_stems[kind] = s
	return s


## A picture's name as `e` wears it: tinted for a tough guy.
static func look(e: Enemy, name: String) -> String:
	var tint = TINTS.get(e.kind)
	if tint == null or art == null:
		return name
	return art.tinted_art(name, tint)


## The weave in a stumbling drunk's walk this moment.
static func wobble(e: Enemy) -> float:
	return float(STUMBLE[e.kind]) * sin(e.pose * 2.3 + e.x * .7)


## Turns `e` into `kind` (a variant or a tough guy), its health full again if
## it was.
static func become(e: Enemy, kind: String) -> void:
	var full := e.hp >= e.max_hp
	e.kind = kind
	refresh(e)
	if full:
		e.hp = e.max_hp


## What a kind sets on an enemy (after a save gave it back a variant's kind).
static func refresh(e: Enemy) -> void:
	var spec: Array = Enemy.KINDS[e.kind]
	var d: Dictionary = Enemy.DEFS[e.kind]
	e.brain = String(d.get("brain", e.kind))
	e.speed = float(spec[1])
	e.radius = float(spec[2])
	e.height = float(spec[3])
	e.hostile = bool(spec[4])
	e.max_hp = float(spec[0])
	e.hp = minf(e.hp, e.max_hp)
	e.swims = bool(d.get("swims", false))


## Which of the level's own enemies become variants at this difficulty:
## {index: kind}. No dice: the same chapter at the same difficulty always
## swaps the same ones, so a save made since holds the kinds it had.
static func swaps(level_id: String, kinds: Array, difficulty: int) -> Dictionary:
	var out := {}
	var every: int = EVERY[clampi(difficulty, 0, 3)]
	if every == 0:
		return out
	var seed := 0
	for i in level_id.length():
		seed += level_id.unicode_at(i) * (i + 1)
	for i in kinds.size():
		var kind := String(kinds[i])
		if VARIANT_OF.has(kind) and (i * 7 + seed) % every == 0:
			out[i] = VARIANT_OF[kind]
	return out


## The one of the level's own enemies (an index) that is its tough guy, or
## -1: of the regulars of his kind standing about (not patrolling, not held
## back), the middle half by distance from the start, the one with most set
## dressing round him (props, boards and scenery within 3 cells).
static func tough_pick(game, taken: Dictionary) -> int:
	var tough := String(TOUGH.get(game.level.id, ""))
	if tough == "":
		return -1
	var base := String(Enemy.DEFS[tough].get("swap", ""))
	# How far each is from the start on foot, through the doors.
	var walk := FlowField.new(game.level, game.flow)
	walk.reach = 100000
	walk.doors_open = true
	walk.every_door = true
	walk.update(float(game.level.spawn[0]), float(game.level.spawn[1]), 0.0)
	var rows: Array = []
	var far := 0
	for i in game.enemy_ids.size():
		var e: Enemy = game.enemies[i]
		var steps := walk.distance(e.x, e.y)
		if steps < FlowField.FAR:
			far = maxi(far, steps)
		if e.kind != base or taken.has(i) or e.dormant or not e.alive or not e.route.is_empty():
			continue
		if steps < FlowField.FAR:
			rows.append([steps, i])
	if rows.is_empty():
		return -1
	rows.sort()
	# Mid-chapter: from two fifths to three quarters of the way out.
	var from := rows.size()
	var to := 0
	for k in rows.size():
		if int(rows[k][0]) >= far * .4 and int(rows[k][0]) <= far * .75:
			from = mini(from, k)
			to = k + 1
	if from >= to:
		from = rows.size() / 4
		to = maxi(from + 1, rows.size() - rows.size() / 4)
	var best := -1
	var most := -1
	for row: Array in rows.slice(from, to):
		var e: Enemy = game.enemies[int(row[1])]
		var count := 0
		for p in game.level.props:
			if Vector2(float(p[1]) - e.x, float(p[2]) - e.y).length_squared() < 9.0:
				count += 1
		for b: LevelData.Billboard in game.level.billboards:
			if Vector2(b.x - e.x, b.y - e.y).length_squared() < 9.0:
				count += 1
		for s: LevelData.Scenery in game.world.scenery:
			if Vector2(s.x - e.x, s.y - e.y).length_squared() < 9.0:
				count += 1
		if count > most:
			most = count
			best = int(row[1])
	return best


# --------------------------------------------------------------- the shot


## A variant's own attack (true), or false to leave it to its brain: the
## drunk's jug every few pulls, and a billy's or coot's shot with its own
## numbers (barrels, blast, fan, aim, wild).
static func attack(e: Enemy, game, direction: float, distance: float, eye: float) -> bool:
	var d: Dictionary = Enemy.DEFS[e.kind]
	if d.has("throws") and e.attacks % int(d["throws"]) == 0:
		_jug(e, game, direction, distance, eye)
		return true
	if not (d.has("barrels") or d.has("wild")) or (e.brain != "billy" and e.brain != "coot"):
		return false
	var close := e.brain == "billy"
	var chance := maxf(.24, .88 - distance * .104) if close else maxf(.34, .83 - distance * .060)
	chance *= float(d.get("aim", 1.0))
	var blast: Array = d.get("blast", [14, 8] if close else [7, 7])
	var damage := int(blast[0]) if distance < 2.4 else int(blast[1])
	e.cooldown = float(d.get("delay", 1.45 if close else 1.58)) + game.rng.uniform(.04, .33)
	game.sound_at("enemy_scatter" if close else "enemy_pistol", e.x, e.y, .9)
	direction += game.rng.uniform(-1.0, 1.0) * float(d.get("wild", 0.0))
	game.burst(
		e.x + cos(direction) * e.radius, e.y + sin(direction) * e.radius, eye, "spark", 3, 1.2
	)
	var p = game.player
	var miss := absf(Enemy.angle_delta(atan2(p.y - e.y, p.x - e.x), direction))
	var fan := float(d.get("fan", .23 if close else .11))
	for _k in int(d.get("barrels", 1)):
		var in_way := _in_way(e, game, direction, distance)
		if in_way != null:
			if game.rng.random() < maxf(.35, chance):
				in_way.hurt(float(damage), game, false, false, e)
			continue
		var odds := chance * (.79 if p.crouched else 1.0) * maxf(0.0, 1.0 - miss / fan * .60)
		odds = minf(.97, odds * float(game.sharpness))
		if miss < fan and game.rng.random() < odds:
			game.damage(damage, [e.x, e.y], "FIRE")
	return true


## One of their own between `e` and the player along `direction`, or null.
static func _in_way(e: Enemy, game, direction: float, distance: float) -> Enemy:
	var in_way: Enemy = null
	var nearest := distance
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile:
			continue
		var ox: float = other.x - e.x
		var oy: float = other.y - e.y
		var along := ox * cos(direction) + oy * sin(direction)
		if along > .3 and along < nearest:
			if absf(ox * sin(direction) - oy * cos(direction)) < other.radius + .06:
				nearest = along
				in_way = other
	return in_way


## The drunk's jug, lobbed like the bottle tosser's bottle (it smashes where
## the player stood: glass).
static func _jug(e: Enemy, game, direction: float, distance: float, eye: float) -> void:
	e.cooldown = 2.1
	var p = game.player
	var flight := minf(1.32, maxf(.48, distance / 6.1))
	var throw := maxf(.45, (distance - .34) / flight)
	var target_z: float = game.world.stand(p)
	var sx := e.x + cos(direction) * .34
	var sy := e.y + sin(direction) * .34
	if game.world.blocked(sx, sy, .045, eye):
		return
	game.launch(
		sx,
		sy,
		eye,
		direction,
		throw,
		"fair_bottle",
		(target_z + .06 - eye) / flight + 2.75 * flight,
		true,
		0,
		flight
	)
	game.sound_at("tosser_throw", e.x, e.y, .85)


# -------------------------------------------------------------- the door


## A hit on a shield deputy (ShipAliens.soak hands it here): from the front,
## unless the door is swung aside to fire, the door takes it; a blast tears
## at the door wherever it comes from. Returns what gets through to him.
static func soak(
	e: Enemy, amount: float, game, how: String, explosive: bool, pressure: bool, by
) -> float:
	var keeper = game.features.get("variants")
	if keeper == null or by != null or keeper.door_left(e) <= 0.0:
		return amount
	if pressure or (ShipAliens.SHIELD_PASSES.has(how) and not explosive):
		return amount
	# A shot comes from the player; a blast from its middle.
	var from := Vector2(game.player.x, game.player.y)
	if explosive and game.hit_point != Vector3.INF:
		from = Vector2(game.hit_point.x, game.hit_point.y)
	var toward := atan2(from.y - e.y, from.x - e.x)
	var front := (
		e.windup <= 0.0 and e.volley == 0 and absf(Enemy.angle_delta(toward, e.angle)) <= DOOR_ARC
	)
	if explosive:
		keeper.tear(e, amount * 1.5)
		return amount * (.5 if front else 1.0)
	if not front:
		return amount
	keeper.tear(e, amount)
	if game.clock - e.struck_at > .14:
		game.sound_at(ShipAliens.cue(game, "tailgate_clang", "ricochet"), e.x, e.y, .7)
	var floor_z: float = game.world.stand(e)
	game.burst(e.x + cos(toward) * .36, e.y + sin(toward) * .36, floor_z + .7, "spark", 3, 1.1)
	return amount * DOOR_LEAK


## The car door, painted once: rust-red sheet metal under a dark window,
## a chrome handle, a few dents and bullet dings. 1997 pixels, no file.
static func paint_door(assets: Assets) -> void:
	if assets == null or assets.has_art(DOOR_PICTURE):
		return
	var data := PackedByteArray()
	data.resize(DOOR_W * DOOR_H * 4)
	for y in DOOR_H:
		for x in DOOR_W:
			var o := (y * DOOR_W + x) * 4
			# The door's outline: a sloped window frame at the top front.
			var top := 2 + int(maxf(0.0, 9.0 - x) * .6)
			if y < top or x < 1 or x > DOOR_W - 2 or y > DOOR_H - 2:
				continue
			var grain := float((x * 7 + y * 13) % 5) * 4.0
			var c := Color8(int(132 + grain), int(46 + grain * .4), int(30 + grain * .2))
			if y < 13 and x > 3 and x < DOOR_W - 4 and y > top + 1:
				# The window: dark glass, a streak of sky.
				c = Color8(36, 48, 58) if (x + y) % 9 != 0 else Color8(118, 132, 140)
			elif y == 13 or y == 14:
				c = Color8(176, 172, 160)
			elif y > 17 and y < 20 and x > DOOR_W - 10 and x < DOOR_W - 4:
				c = Color8(208, 204, 196)
			elif (x - 9) * (x - 9) + (y - 24) * (y - 24) < 9:
				c = Color8(104, 34, 24)
			elif (x == 6 and y == 21) or (x == 18 and y == 27) or (x == 23 and y == 16):
				c = Color8(20, 16, 14)
			elif x == 1 or x == DOOR_W - 2 or y == DOOR_H - 2:
				c = Color8(84, 30, 22)
			data[o] = c.r8
			data[o + 1] = c.g8
			data[o + 2] = c.b8
			data[o + 3] = 255
	assets.put_art(DOOR_PICTURE, DOOR_W, DOOR_H, data)
