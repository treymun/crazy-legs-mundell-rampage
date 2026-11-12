## A living county: before they notice the player, the county's hands are
## busy with something by where they stand, picked when a chapter starts from
## the props, boards and scenery near each one's place in the level (no plan
## changes): drinking by a cooler or a still, playing cards round a table,
## fixing a truck, feeding the hogs, chopping wood, napping on a porch couch,
## fishing, watching the television, smoking under a lamp, and the aliens
## probing a cow or a crate of specimens. They face the thing and show it
## with the cels they have (fidget, recover, aim) on a loop of their own, a
## puff or a spark now and then (features/squad_feature.gd draws those), and
## being busy they are slower to notice (`notice`). Startled out of it they
## fumble (Squad.startled); hit from behind unaware, they are stunned.
class_name IdleLife
extends RefCounted

## Activity -> pieces of the names of things that start it. Earlier rows win
## a tie at the same distance.
const BY_THINGS := [
	["probing", ["cow_tube", "specimen", "alien_console", "alien_crate", "saucer"]],
	["watching", ["tv"]],
	["cards", ["picnic_table", "boil_table", "table", "trophy"]],
	[
		"drinking",
		[
			"jug",
			"mash_barrel",
			"cooler",
			"ice_chest",
			"still",
			"bottles",
			"cancan",
			"cans",
			"jukebox",
			"backstock",
			"vending",
			"copper_vat",
			"soda"
		]
	],
	["napping", ["porch_couch", "rocker", "bunk", "bathtub", "laundry", "couch"]],
	["chopping", ["log_pile", "axe_stump", "lumber", "saw_blade", "pallet"]],
	["feeding", ["hay", "feed", "giant_hog", "coop", "trough"]],
	[
		"tinkering",
		[
			"wreck",
			"pickup_truck",
			"engine",
			"tool_chest",
			"derby",
			"stock_car",
			"monster_truck",
			"dump_truck",
			"forklift",
			"outboard",
			"tire",
			"nitro_rack",
			"generator",
			"mine_cart"
		]
	],
	["fishing", ["crawfish", "net_rack", "gator_hide", "cypress", "reeds"]],
	["smoking", ["lamp", "lantern", "gas_cans", "propane", "utilitypole", "pump"]],
]
## How far from its place a thing may stand and still set the activity.
const REACH := 2.6
## How much of its usual notice range a hand busy at each keeps (EASY; the
## harder the difficulty the nearer to all of it).
const NOTICE := {
	"napping": .45,
	"watching": .65,
	"cards": .7,
	"tinkering": .7,
	"probing": .7,
	"drinking": .75,
	"fishing": .75,
	"chopping": .8,
	"feeding": .85,
	"smoking": .9,
}


## Everything in the level an activity can be about: [name, place].
static func things(game) -> Array:
	var out: Array = []
	for p in game.level.props:
		out.append([String(p[0]), Vector2(float(p[1]), float(p[2]))])
	for b: LevelData.Billboard in game.level.billboards:
		out.append([b.image, Vector2(b.x, b.y)])
	for s: LevelData.Scenery in game.world.scenery:
		out.append([s.kind, Vector2(s.x, s.y)])
	return out


## What `e` (the level's own enemy number `index`, placed at `at`) does
## before it notices anything, from `about` (things()): [activity, the
## thing's place] or [] for nothing. Aliens probe a critter (a pig, a
## chicken) or their specimens.
static func pick(game, e: Enemy, at: Vector2, index: int, about: Array) -> Array:
	var best := ""
	var best_at := Vector2.INF
	var near := REACH * REACH
	var alien := Enemy.PLASMA.has(e.kind)
	for row: Array in about:
		var d := at.distance_squared_to(row[1])
		if d >= near:
			continue
		var what := _activity(String(row[0]))
		if what == "" or (what == "probing" and not alien):
			continue
		near = d
		best = what
		best_at = row[1]
	if alien:
		for other: Enemy in game.enemies:
			if (
				not other.hostile
				and other.brain != "bessie"
				and at.distance_to(Vector2(other.x, other.y)) < 3.2
			):
				return ["probing", Vector2(other.x, other.y)]
	if best == "" and index % 3 == 0 and Enemy.FIDGET_CELS.has(e.kind):
		# Nothing by him: he loafs and smokes, facing the way he stood.
		return ["smoking", at + Vector2(cos(e.angle), sin(e.angle))]
	if best == "":
		return []
	return [best, best_at]


static func _activity(name: String) -> String:
	for row: Array in BY_THINGS:
		for piece: String in row[1]:
			if name.contains(piece):
				return String(row[0])
	return ""


## The share of its notice range a busy hand keeps.
static func notice(e: Enemy, game) -> float:
	var m = e.mind
	if m.activity == "" or not at_it(e):
		return 1.0
	var keep := float(NOTICE.get(m.activity, 1.0))
	return lerpf(keep, 1.0, float(game.difficulty) * .2)


static func at_it(e: Enemy) -> bool:
	var m = e.mind
	return absf(e.x - m.spot.x) < .5 and absf(e.y - m.spot.y) < .5


## Its activity this tick (it has one and has noticed nothing): back to its
## place if it wandered (an investigation), then facing the thing, swaying,
## the feeder pacing a step and back. False when it has none.
static func act(e: Enemy, dt: float, game) -> bool:
	var m = e.mind
	if m.activity == "":
		return false
	var t: float = e.pose + m.phase
	var home: Vector2 = m.spot
	if m.activity == "feeding" and fmod(t, 8.0) < 4.0:
		home = m.spot + (m.focus - m.spot).orthogonal().normalized() * .9
	var gap := home - Vector2(e.x, e.y)
	if gap.length() > .22:
		if gap.length() > 9.0:
			m.activity = ""
			return false
		e.follow(dt, game, gap.angle(), .45 if m.activity == "feeding" else .55)
		return true
	var face: float = (m.focus - Vector2(e.x, e.y)).angle()
	var sway := .22 * sin(t * .55)
	if m.activity == "tinkering" or m.activity == "chopping":
		sway = .1 * sin(t * 1.9)
	elif m.activity == "napping":
		sway = 0.0
	e.angle = face + sway
	if absf(cos(e.angle)) > .38:
		e.face_left = cos(e.angle) < 0.0
	return true


## The cel its activity shows now, seen from `observer` (only when it faces
## them: the cels are drawn from the front), or 0 for its plain standing cel.
static func frame(e: Enemy, observer) -> Variant:
	var m = e.mind
	if m.activity == "" or not at_it(e) or observer == null:
		return 0
	var bearing := atan2(float(observer[1]) - e.y, float(observer[0]) - e.x)
	if absf(Enemy.angle_delta(bearing, e.angle)) > PI / 3.0:
		return 0
	var t: float = e.pose + m.phase
	var fidgets := Enemy.FIDGET_CELS.has(e.kind)
	match m.activity:
		"drinking":
			if fmod(t, 3.4) > 2.3:
				return "fidget" if fidgets else "recover"
		"smoking":
			if fidgets and fmod(t, 4.6) > 3.8:
				return "fidget"
		"watching":
			if fidgets and fmod(t, 6.0) > 5.2:
				return "fidget"
		"cards":
			if fmod(t, 1.9) > 1.15:
				return "recover"
		"tinkering":
			if fmod(t, 1.3) > .6:
				return "recover"
		"chopping":
			return "aim" if fmod(t, 1.2) < .55 else "recover"
		"napping", "fishing":
			return "recover"
		"probing":
			if fmod(t, 2.6) > 1.3:
				return "aim"
		"feeding":
			if fmod(t, 4.0) > 3.0:
				return "recover"
	return 0
