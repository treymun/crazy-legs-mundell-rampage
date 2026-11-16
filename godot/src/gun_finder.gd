## Finding the guns (feature pass 7; features/new_iron.gd keeps what was seen
## and said; all of it looks and sound, never play): a gun lying out that the
## player ain't got yet ("new iron": src/weapons.gd's owned) shines (a warm glint over it and a
## pool of light under it, effects.cfg [light.new_iron]); the automap marks it
## with a little gun in red once it has been seen or smelled (NEW IRON in the
## map's key); USE's prompt names it from `prompt_reach` off when it is looked
## at ("RIP SAW  /  NEW IRON"); Mundell says so the first time one is within
## `smell_reach` ("SMELLS LIKE GUN OIL..."). Campaign and co-op chapters only:
## not County Run, the versus maps, the range or a boss rematch. The chapter's
## tally counts its guns had (GUNS 02 / 03) and the trophy shack's shadow board
## and card show the campaign's guns and what is still out there
## (features/trophy_shack.gd).
## Numbers in data/tuning/effects.cfg [new_iron].
class_name GunFinder
extends RefCounted

## The automap's mark: a red the signs are painted in, its outline, the steel.
const MAP_INK := Color8(236, 76, 52)
const MAP_EDGE := Color8(52, 30, 14)
const MAP_STEEL := Color8(200, 196, 180)
## The little gun on the automap, side on, muzzle to the right: '#' the stock
## and the action in red, '-' the barrel in steel (8 wide, 4 high).
const ICON := ["...-----", "#####---", "###.#...", "##......"]
## The guns each chapter lays out, as a campaign game has them (a level's
## "riveter" is the bowling ball and its "pressure_gun" the cow launcher,
## game_state.gd ALIAS; the riveter and the Copperhead are the range's and the
## 5v5 store's). The hub's card reads this without loading each chapter;
## tools/gun_find_check.gd holds it to the levels.
const CHAPTER_GUNS := {
	"hickston": ["crossbow", "shotgun", "slingblade", "rifle", "ripsaw", "armgun", "teat_gun"],
	"fair": ["shotgun", "bottle_launcher", "rifle", "powder_keg"],
	"sawmill": ["shotgun", "rifle", "bowling_ball"],
	"quarry": ["shotgun", "rifle", "cow_launcher"],
	"bayou": ["shotgun", "rifle", "crossbow"],
	"speedway": ["shotgun", "rifle", "crossbow", "bottle_launcher"],
	"mothership": ["armgun", "bottle_launcher", "powder_keg"],
}
const PATH := "res://data/tuning/effects.cfg"


## A [new_iron] number from effects.cfg.
static func tuned(key: String) -> float:
	var raw: Variant = Tuning.file(PATH).get_value("new_iron", key, 0.0)
	if raw is int:
		var whole: int = raw
		return float(whole)
	var part: float = raw
	return part


## Whether the guns are found here: a campaign chapter, played alone or in
## co-op, not a boss rematch.
static func on(g: Game) -> bool:
	if g.level == null or not Campaign.ORDER.has(g.level.id) or g.in_hub:
		return false
	if BossRematch.active(g):
		return false
	var mode := Modes.mode_of(g)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


## The campaign's guns, as Mundell's shadow board in the trophy shack hangs
## them (tools/art/build_gun_signs.gd paints it from this order: five a row).
const BOARD := [
	"crowbar",
	"revolver",
	"shotgun",
	"crossbow",
	"rifle",
	"ripsaw",
	"armgun",
	"tnt",
	"slingblade",
	"bottle_launcher",
	"bowling_ball",
	"powder_keg",
	"cow_launcher",
	"teat_gun",
]


## The gun a pickup gives in a campaign game ([] for ammo, food, keys).
static func guns_of(item: String) -> Array:
	var gun := str(GameState.ALIAS.get(item, item))
	return [gun] if Weapons.NAMES.has(gun) else []


## Whether `item` is a gun `armory` ain't got.
static func unclaimed(item: String, armory: Weapons.Armory) -> bool:
	for gun: String in guns_of(item):
		if not armory.owned[Weapons.NAMES.find(gun)]:
			return true
	return false


## A gun's name as the pickup says it, without the number key ("SLING BLADE").
static func label(item: String) -> String:
	var at := Weapons.NAMES.find(item)
	if at < 0:
		return item.to_upper()
	var name := str(Weapons.LABELS[at])
	var cut := name.find(" [")
	return name.substr(0, cut) if cut > 0 else name


## Where a pickup lies (its deck, or the ground).
static func lies(g: Game, entry: Array) -> float:
	var x: float = entry[1]
	var y: float = entry[2]
	return entry[4] if entry.size() > 4 else g.world.elevation(x, y)


## Whether (x, y) lies in a secret room not found yet (a hidden room behind a
## secret door still shut): a gun there neither shines nor goes on the map
## (Mundell can still smell it).
static func in_secret(g: Game, x: float, y: float) -> bool:
	var cell := Vector2i(int(x), int(y))
	for door: LevelData.Door in g.world.doors:
		if not door.secret or door.discovered:
			continue
		for room: Array in g.level.hidden_rooms:
			if room[0] == Vector2i(door.x, door.y):
				var box: Vector4i = room[1]
				if cell.x >= box.x and cell.x <= box.z and cell.y >= box.y and cell.y <= box.w:
					return true
	return false


## A place in the level as a key that a save keeps (a pickup's uid is handed
## out again on load).
static func spot(x: float, y: float) -> Vector2:
	return Vector2(snappedf(x, .01), snappedf(y, .01))


## The place in g.pickups of the gun `p` ain't got, within `far` and in sight,
## that `p` looks at (within `facing`, a cosine; of a row of them the one most
## in the middle of the view); -1 when none.
static func looked_at(g: Game, p: Player, far: float, facing: float) -> int:
	var best := -1
	var best_dot := -INF
	var look := Vector2(cos(p.angle), sin(p.angle))
	for i in g.pickups.size():
		var entry: Array = g.pickups[i]
		var item := str(entry[0])
		var x: float = entry[1]
		var y: float = entry[2]
		if absf(x - p.x) > far or absf(y - p.y) > far or not Weapons.NAMES.has(item):
			continue
		var to := Vector2(x - p.x, y - p.y)
		var d := to.length()
		var dot := to.normalized().dot(look) if d > .01 else 1.0
		if d > far or dot < facing or dot <= best_dot or not unclaimed(item, p.armory):
			continue
		if not g.world.visible(p.x, p.y, x, y, p.eye, lies(g, entry) + .2):
			continue
		best = i
		best_dot = dot
	return best


## USE's prompt for a gun the player ain't got, looked at from further off
## than it is picked up: its name and that it is new iron.
static func far_prompt(g: Game) -> String:
	if not on(g):
		return ""
	var i := looked_at(g, g.player, tuned("prompt_reach"), tuned("prompt_facing"))
	if i < 0:
		return ""
	var entry: Array = g.pickups[i]
	return label(str(entry[0])) + "  /  NEW IRON"


## The glint over each gun the local player ain't got that is in view: a
## spark most of the time, now and then a cross and a star (looks only; its
## beat is the clock's and the place's, never a dice roll).
static func shines(g: Game, out: Array) -> void:
	var armory := g.local_player.armory
	var size := tuned("shine_size")
	for entry: Array in g.pickups:
		var item := str(entry[0])
		if not Weapons.NAMES.has(item):
			continue
		var x: float = entry[1]
		var y: float = entry[2]
		if not g.in_view(x, y, 1.0) or not unclaimed(item, armory) or in_secret(g, x, y):
			continue
		var beat := fmod(g.clock * .7 + x * .37 + y * .71, 1.6)
		var frame := 1 if beat < .1 or (beat >= .2 and beat < .3) else 2 if beat < .2 else 0
		var spr := g.pooled(
			x, y, "fx_gun_shine_%d" % frame, size, lies(g, entry) + tuned("shine_lift")
		)
		spr.glow = true
		out.append(spr)


## The pool of light under each gun near `p` that the local player ain't got
## (effects.cfg [light.new_iron]).
static func lights(g: Game, p: Player) -> Array:
	var out: Array = []
	var armory := g.local_player.armory
	for entry: Array in g.pickups:
		var item := str(entry[0])
		var x: float = entry[1]
		var y: float = entry[2]
		if absf(x - p.x) > 12.0 or absf(y - p.y) > 12.0 or not Weapons.NAMES.has(item):
			continue
		if not unclaimed(item, armory) or in_secret(g, x, y):
			continue
		var l: Variant = Effects.light("new_iron", x, y, lies(g, entry) + .45, 1.0, g.clock)
		if l != null:
			out.append(l)
	return out


## Each gun the local player ain't got and has seen or smelled (`seen`, by
## spot()) on the automap (`map`, the open GameAutomap); whether any was drawn.
static func draw_map(c: Canvas, map: GameAutomap, g: Game, seen: Dictionary) -> bool:
	var drew := false
	var marks: Array = []
	var armory := g.local_player.armory
	for entry: Array in g.pickups:
		var item := str(entry[0])
		if not Weapons.NAMES.has(item) or not unclaimed(item, armory):
			continue
		var x: float = entry[1]
		var y: float = entry[2]
		if not seen.has(spot(x, y)) or in_secret(g, x, y):
			continue
		var at := map.point(x, y)
		if not map.shows(at) or marks.any(func(m: Vector2) -> bool: return m.distance_to(at) < 4.0):
			continue  # off the window, or a gun lying beside one already marked
		marks.append(at)
		icon(c, int(at.x) - 4, int(at.y) - 2)
		drew = true
	return drew


## The little gun with its top left at (x, y): outlined in the map's dark, the
## stock and action red, the barrel steel.
static func icon(c: Canvas, x: int, y: int) -> void:
	for r in ICON.size():
		var row: String = ICON[r]
		for k in row.length():
			if row[k] != ".":
				c.fill_rect(x + k - 1, y + r - 1, 3, 3, MAP_EDGE)
	for r in ICON.size():
		var row: String = ICON[r]
		for k in row.length():
			if row[k] == "#":
				c.fill_rect(x + k, y + r, 1, 1, MAP_INK)
			elif row[k] == "-":
				c.fill_rect(x + k, y + r, 1, 1, MAP_STEEL)


## The guns a chapter lays out, each gun once.
static func chapter_guns(level_id: String) -> Array:
	var guns: Array = CHAPTER_GUNS.get(level_id, [])
	return guns.duplicate()


## The chapter tally's row: of the guns this chapter lays out, how many the
## player has ([] where it lays out none, or off the campaign).
static func tally(g: Game) -> Array:
	if not on(g):
		return []
	var guns := chapter_guns(g.level.id)
	if guns.is_empty():
		return []
	var had := 0
	for gun: String in guns:
		if g.local_player.armory.owned[Weapons.NAMES.find(gun)]:
			had += 1
	return ["GUNS", "%02d / %02d" % [had, guns.size()]]
