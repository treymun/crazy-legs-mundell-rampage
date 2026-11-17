## The county's hazards a man can be driven into (features/brawl.gd): where
## they stand in a level and which one has him. Found from the props the
## levels already stand (hits.cfg [hazard] `images`: a saw, a chipper, a bug
## zapper, a hot fence, a burn barrel, a well, a cattle guard, a crusher),
## from deep or running water (BayouBrains.wet_at) and from the hogs (a live
## one within `hog_reach`). Arithmetic on the level and the enemies only, the
## same on every machine.
class_name BrawlHazards
extends RefCounted

static var IMAGES: Dictionary = HitData.value("hazard", "images", {})
static var HOG_REACH: float = HitData.value("hazard", "hog_reach", 2.6)
static var WATER_AHEAD: float = HitData.value("hazard", "water_ahead", .45)
static var WATER_LEAST: float = HitData.value("hazard", "water_least", 2.0)
## Each kind's section ([hazard.<kind>]), read once.
static var _kinds := {}


## [hazard.<kind>]'s `key`.
static func value(kind: String, key: String, fallback: Variant) -> Variant:
	if not _kinds.has(kind):
		_kinds[kind] = HitData.section("hazard." + kind)
	var section: Dictionary = _kinds[kind]
	return section.get(key, fallback)


## The level's hazard props: [kind, x, y], in the boards' order.
static func spots(world: LevelData) -> Array:
	var out: Array = []
	for board: LevelData.Billboard in world.billboards:
		if board.hidden or not IMAGES.has(board.image):
			continue
		out.append([str(IMAGES[board.image]), board.x, board.y])
	return out


## The hazard prop that has `e` where it stands now: [kind, x, y], or [].
static func prop_at(spots_list: Array, e: Enemy) -> Array:
	for spot: Array in spots_list:
		var kind: String = spot[0]
		var sx: float = spot[1]
		var sy: float = spot[2]
		var reach: float = value(kind, "reach", .8)
		reach += e.radius
		var dx := e.x - sx
		var dy := e.y - sy
		if absf(dx) < reach and absf(dy) < reach and dx * dx + dy * dy < reach * reach:
			return spot
	return []


## Whether a man sliding at (vx, vy) goes into water here: wet a little
## ahead of him, going fast enough, and not one who swims.
static func into_water(world: LevelData, e: Enemy, vx: float, vy: float) -> bool:
	if e.swims:
		return false
	var speed := sqrt(vx * vx + vy * vy)
	if speed < WATER_LEAST:
		return false
	var ax := e.x + vx / speed * (e.radius + WATER_AHEAD)
	var ay := e.y + vy / speed * (e.radius + WATER_AHEAD)
	return BayouBrains.wet_at(world, ax, ay) and BayouBrains.wet_at(world, e.x, e.y)


## The hogs near (x, y) (live pigs within HOG_REACH), nearest first.
static func hogs_near(enemies: Array, x: float, y: float) -> Array:
	var out: Array = []
	for o: Enemy in enemies:
		if o.brain != "pig" or not o.alive or o.dormant:
			continue
		var d := Vector2(o.x - x, o.y - y).length()
		if d < HOG_REACH:
			out.append(o)
	return out
