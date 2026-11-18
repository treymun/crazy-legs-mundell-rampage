## What BLUE's nose and eyes find for him (features/hound.gd): a secret door
## not found yet and where to bay at it from, new iron lying out, a pickup out
## of the player's sight to point at, something worth fetching, the hand or
## pickup a player's sights are on, and whether a hand is one he can take.
## Since pass 10 also a hand awake round a corner, a still or scrap to wag
## at, a siren to howl at. Plain questions of the game: nothing here changes
## play or rolls dice.
class_name HoundNose
extends RefCounted

const FILE := "res://data/tuning/hound.cfg"
## The hands he never takes on: the ones that fly or swim, and the bosses
## (Enemy.BOSS_TITLES) besides.
const NO_PIN := ["skeeter", "saucer", "drone", "probe", "lantern", "crawler", "gator", "cow"]
## What he carries: the food and every kind of rounds the game counts (no
## keys, quest pieces or guns; a stick of dynamite he leaves be).
const NOT_FETCHED := ["dynamite"]
## The pictures of what sets him wagging: a moonshine still, a copper vat, a
## shine tank (and the scrap lying about, a pickup scrap_*).
const TREATS := [
	"town_still", "town_big_still", "town_copper_vat", "town_shine_tank", "wing_quarry_still"
]


## A [hound] number from hound.cfg.
static func tuned(key: String) -> float:
	var raw: Variant = Tuning.file(FILE).get_value("hound", key, 0.0)
	if raw is int:
		var whole: int = raw
		return float(whole)
	var part: float = raw
	return part


## Whether the hounds come along here: HOUND DOG on, a campaign chapter (not
## the Crossroads, the range or a boss rematch), alone or in co-op. Off in
## the versus modes and County Run (its runs and the daily board are set for
## one man and his guns).
static func on(g: Game) -> bool:
	if not g.hound_on or g.level == null or g.in_hub:
		return false
	if not Campaign.ORDER.has(g.level.id) or BossRematch.active(g):
		return false
	var mode := Modes.mode_of(g)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


## Whether hand `e` is one he can go for: up, awake, hostile, not a boss, not
## one that flies or swims.
static func takes(e: Enemy) -> bool:
	return (
		e.alive
		and e.hostile
		and not e.dormant
		and not Enemy.BOSS_TITLES.has(e.kind)
		and not NO_PIN.has(e.brain)
		and not NO_PIN.has(e.kind)
		and not e.swims
	)


## The hand he would go for on his own from (x, y): awake, within `reach`, in
## his sight, not standing in harm (`danger`, HoundLegs.dangers), and badly
## hurt (under `below` of its health), right on top of player `p` or going
## for them close by; of several the one he ought to (pass 10): one on his
## player first, then a hurt one, then the nearest, and one a player's
## sights are not already on (they will shoot it: he takes the flanker).
## Null when none. `taken` names hands another hound already has.
static func foe_near(
	g: Game,
	x: float,
	y: float,
	z: float,
	p: Player,
	reach: float,
	below: float,
	taken: Dictionary,
	danger: Array = []
) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for e: Enemy in g.enemies:
		if absf(e.x - x) > reach or absf(e.y - y) > reach or not e.alerted or not takes(e):
			continue
		if taken.has(e.uid):
			continue
		var d := Vector2(e.x - x, e.y - y).length()
		if d >= reach:
			continue
		var to_p := Vector2(e.x - p.x, e.y - p.y).length()
		var chasing := false
		if e.target is Player:
			var aim: Player = e.target
			chasing = aim == p
		var on_p := to_p < 3.0 or (to_p < 5.0 and chasing)
		var hurt := e.hp <= e.max_hp * below
		if not hurt and not on_p:
			continue
		var score := d - (3.0 if on_p else 0.0) - (1.5 if hurt else 0.0)
		if HoundLegs.before_sights(g, e.x, e.y, 14.0, .97):
			score += 2.0
		if score >= best_score:
			continue
		if not danger.is_empty() and HoundLegs.harm(g, danger, e.x, e.y, .3):
			continue
		if not g.world.visible(x, y, e.x, e.y, z + .4, g.world.stand(e) + .6):
			continue
		best = e
		best_score = score
	return best


## A hand awake within `reach` of (x, y) that player `p` cannot see, while
## none they can see is near (the fight is not on yet): he smells it round
## the corner and growls (pass 10). Not one in `warned` (uid -> true), not a
## boss. Null when none.
static func unseen_foe(
	g: Game, x: float, y: float, p: Player, reach: float, warned: Dictionary
) -> Enemy:
	var lurk: Enemy = null
	var lurk_d := reach
	for e: Enemy in g.enemies:
		if not e.alive or not e.hostile or e.dormant:
			continue
		var near_p := absf(e.x - p.x) < 12.0 and absf(e.y - p.y) < 12.0
		var near_d := absf(e.x - x) < reach and absf(e.y - y) < reach
		if not near_p and not near_d:
			continue
		var seen := g.world.visible(p.x, p.y, e.x, e.y, p.eye, g.world.stand(e) + .8)
		if seen and near_p:
			return null  # one in sight: the fight is his player's to see
		if seen or not near_d or warned.has(e.uid) or Enemy.BOSS_TITLES.has(e.kind):
			continue
		var d := Vector2(e.x - x, e.y - y).length()
		if d < lurk_d:
			lurk = e
			lurk_d = d
	return lurk


## A still standing or scrap lying within `reach` of (x, y), on his floor, in
## his sight and not wagged at yet (`bayed`): its place, or Vector2.INF.
static func treat_near(
	g: Game, x: float, y: float, z: float, reach: float, bayed: Dictionary
) -> Vector2:
	for board: LevelData.Billboard in g.world.billboards:
		if board.hidden or not TREATS.has(board.image):
			continue
		if absf(board.x - x) > reach or absf(board.y - y) > reach:
			continue
		var at := Vector2(board.x, board.y)
		if bayed.has(key(at)) or at.distance_to(Vector2(x, y)) > reach:
			continue
		if not g.world.visible(x, y, at.x, at.y, z + .4, g.world.elevation(at.x, at.y) + .6):
			continue
		return at
	for entry: Array in g.pickups:
		if not str(entry[0]).begins_with("scrap_"):
			continue
		var px: float = entry[1]
		var py: float = entry[2]
		if absf(px - x) > reach or absf(py - y) > reach:
			continue
		var at := Vector2(px, py)
		if bayed.has(key(at)) or GunFinder.in_secret(g, px, py):
			continue
		var lies := GunFinder.lies(g, entry)
		if absf(lies - z) > .4 or not g.world.visible(x, y, px, py, z + .4, lies + .2):
			continue
		return at
	return Vector2.INF


## Whether a still stands at `at` (not scrap): Mundell has a word for that.
static func still_at(g: Game, at: Vector2) -> bool:
	for board: LevelData.Billboard in g.world.billboards:
		if TREATS.has(board.image) and Vector2(board.x, board.y).distance_to(at) < .05:
			return true
	return false


## Whether a siren wails for him now: the twister's warning or the raid's
## (heard everywhere, their first seconds), a cruiser with its siren on the
## track within `reach` of (x, y).
static func siren_near(g: Game, x: float, y: float, reach: float) -> bool:
	var ev: CountyEvents = g.features.get("events")
	if ev != null and (ev.kind == "twister" or ev.kind == "raid") and ev.phase == 0:
		if g.clock - ev.since < 4.0:
			return true
	var laps: HoundLegs.RaceLaps = g.features.get("race_laps")
	if laps == null or laps.total <= 0.0 or not laps.spec.get("siren", false):
		return false
	for car: Array in laps.cars:
		var speed: float = car[1]
		if speed <= 0.0:
			continue
		var along: float = car[0]
		var at: Vector2 = laps._at(along)[0]
		if at.distance_to(Vector2(x, y)) < reach:
			return true
	return false


## Whether any hand awake is within `reach` of (x, y): no time to sniff.
static func fight_near(g: Game, x: float, y: float, reach: float) -> bool:
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and e.alerted and not e.dormant:
			if absf(e.x - x) < reach and absf(e.y - y) < reach:
				return true
	return false


## The open cell beside secret door `door` on the side away from its hidden
## room, nearest (x, y) (Vector2.INF when none).
static func door_front(g: Game, door: LevelData.Door, x: float, y: float) -> Vector2:
	var box := Vector4i(-1, -1, -2, -2)
	for room: Array in g.level.hidden_rooms:
		if room[0] == Vector2i(door.x, door.y):
			box = room[1]
	var best := Vector2.INF
	var best_d := INF
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := Vector2i(door.x, door.y) + step
		if c.x >= box.x and c.x <= box.z and c.y >= box.y and c.y <= box.w:
			continue
		var at := Vector2(c.x + .5, c.y + .5)
		if g.world.blocked(at.x, at.y, .2):
			continue
		var d := at.distance_to(Vector2(x, y))
		if d < best_d:
			best_d = d
			best = at
	return best


## A secret door not found yet within `reach` of (x, y) he can see the front
## of, and not bayed at (`bayed`: spot key -> when): [front, the door's
## middle], or [] when none.
static func secret_near(
	g: Game, x: float, y: float, z: float, reach: float, bayed: Dictionary
) -> Array:
	for door: LevelData.Door in g.world.doors:
		if not door.secret or door.discovered or door.opened:
			continue
		var mid := Vector2(door.x + .5, door.y + .5)
		if absf(mid.x - x) > reach or absf(mid.y - y) > reach or bayed.has(key(mid)):
			continue
		var front := door_front(g, door, x, y)
		if front == Vector2.INF or front.distance_to(Vector2(x, y)) > reach:
			continue
		if not g.world.visible(
			x, y, front.x, front.y, z + .4, g.world.elevation(front.x, front.y) + .4
		):
			continue
		return [front, mid]
	return []


## A gun player `p` ain't got lying out within `reach` of (x, y), in his
## sight and not behind a secret, not bayed at: its place, or Vector2.INF.
static func iron_near(
	g: Game, p: Player, x: float, y: float, z: float, reach: float, bayed: Dictionary
) -> Vector2:
	for entry: Array in g.pickups:
		var item := str(entry[0])
		var px: float = entry[1]
		var py: float = entry[2]
		if absf(px - x) > reach or absf(py - y) > reach or GunFinder.guns_of(item).is_empty():
			continue
		var at := Vector2(px, py)
		if bayed.has(key(at)) or not GunFinder.unclaimed(item, p.armory):
			continue
		if GunFinder.in_secret(g, px, py):
			continue
		var lies := GunFinder.lies(g, entry)
		if lies > z + .5 or not g.world.visible(x, y, px, py, z + .4, lies + .2):
			continue
		return at
	return Vector2.INF


## Whether pickup `item` is one he fetches.
static func fetches(item: String) -> bool:
	if NOT_FETCHED.has(item):
		return false
	return HUD.ITEMS.has(item) or GameState.AMMO.has(item)


## A pickup within `reach` of (x, y) that player `p` cannot see from where
## they stand and he can, on his floor, not behind a secret and not pointed
## at before: its place in g.pickups, or -1.
static func hidden_near(
	g: Game, p: Player, x: float, y: float, z: float, reach: float, bayed: Dictionary
) -> int:
	for i in g.pickups.size():
		var entry: Array = g.pickups[i]
		var item := str(entry[0])
		var px: float = entry[1]
		var py: float = entry[2]
		if absf(px - x) > reach or absf(py - y) > reach or not fetches(item):
			continue
		var at := Vector2(px, py)
		if bayed.has(key(at)) or GunFinder.in_secret(g, px, py):
			continue
		var lies := GunFinder.lies(g, entry)
		if absf(lies - z) > .4 or not g.world.visible(x, y, px, py, z + .4, lies + .2):
			continue
		if g.world.visible(p.x, p.y, px, py, p.eye, lies + .2):
			continue
		return i
	return -1


## Something player `p` needs that lies within `reach` of (x, y) on his
## floor and in his sight: food when they are under `hungry` health, the
## rounds of the gun in their hands when it is nearly out. -1 when none.
static func wanted_near(
	g: Game, p: Player, x: float, y: float, z: float, reach: float, hungry: float
) -> int:
	var want_food := p.health < hungry
	var arms := p.armory
	var want_ammo := ""
	if arms != null and arms.active >= 0 and arms.active < arms.reserve.size():
		for name: String in GameState.AMMO:
			var spec: Array = GameState.AMMO[name]
			var slot: int = spec[0]
			var box: int = spec[1]
			var have: int = arms.reserve[slot] + arms.loaded[slot]
			if slot == arms.active and have <= 2 * box:
				want_ammo = name
	if not want_food and want_ammo == "":
		return -1
	var best := -1
	var best_d := reach
	for i in g.pickups.size():
		var entry: Array = g.pickups[i]
		var item := str(entry[0])
		if not fetches(item) or not ((want_food and HUD.ITEMS.has(item)) or item == want_ammo):
			continue
		var px: float = entry[1]
		var py: float = entry[2]
		var d := Vector2(px - x, py - y).length()
		if d >= best_d or GunFinder.in_secret(g, px, py):
			continue
		var lies := GunFinder.lies(g, entry)
		if absf(lies - z) > .4 or not g.world.visible(x, y, px, py, z + .4, lies + .2):
			continue
		best = i
		best_d = d
	return best


## The hand player `p`'s sights are on (within `reach` and `cone`, a cosine,
## in their sight; of several the one most in the middle), or null.
static func aimed_foe(g: Game, p: Player, reach: float, cone: float) -> Enemy:
	var look := Vector2(cos(p.angle), sin(p.angle))
	var best: Enemy = null
	var best_dot := cone
	for e: Enemy in g.enemies:
		if absf(e.x - p.x) > reach or absf(e.y - p.y) > reach or not takes(e):
			continue
		var to := Vector2(e.x - p.x, e.y - p.y)
		var d := to.length()
		if d > reach or d < .01:
			continue
		# A near body fills more of the view: the cone widens with its size.
		var dot := to.normalized().dot(look) + minf(.04, e.radius / d * .5)
		if dot <= best_dot:
			continue
		if not g.world.visible(p.x, p.y, e.x, e.y, p.eye, g.world.stand(e) + .8):
			continue
		best = e
		best_dot = dot
	return best


## The pickup he fetches that player `p`'s sights are on (as aimed_foe), its
## place in g.pickups, or -1.
static func aimed_pickup(g: Game, p: Player, reach: float, cone: float) -> int:
	var look := Vector2(cos(p.angle), sin(p.angle))
	var best := -1
	var best_dot := cone - .02
	for i in g.pickups.size():
		var entry: Array = g.pickups[i]
		var px: float = entry[1]
		var py: float = entry[2]
		if absf(px - p.x) > reach or absf(py - p.y) > reach or not fetches(str(entry[0])):
			continue
		var to := Vector2(px - p.x, py - p.y)
		var d := to.length()
		if d > reach or d < .6:
			continue
		var dot := to.normalized().dot(look) + minf(.05, .3 / d)
		if dot <= best_dot or GunFinder.in_secret(g, px, py):
			continue
		if not g.world.visible(p.x, p.y, px, py, p.eye, GunFinder.lies(g, entry) + .2):
			continue
		best = i
		best_dot = dot
	return best


## The place in g.pickups of the pickup with stable id `uid`, or -1.
static func pickup_at(g: Game, uid: int) -> int:
	for i in g.pickups.size():
		var entry: Array = g.pickups[i]
		if entry.size() <= 3:
			continue
		var id: int = entry[3]
		if id == uid:
			return i
	return -1


## The hand with stable id `uid`, or null.
static func enemy_of(g: Game, uid: int) -> Enemy:
	if uid <= 0:
		return null
	for e: Enemy in g.enemies:
		if e.uid == uid:
			return e
	return null


## A place as the key of what he has bayed or pointed at.
static func key(at: Vector2) -> String:
	return "%d,%d" % [roundi(at.x * 10.0), roundi(at.y * 10.0)]
