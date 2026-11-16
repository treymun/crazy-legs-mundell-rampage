## New iron: the guns lying out that the local player ain't got yet (src/gun_finder.gd
## says how they are found). This keeps which were seen or smelled (for the
## automap, kept in a save by where they lie) and which Mundell has spoken of,
## glints them, lights them. Looks only: a host leaves it off.
extends GameFeature

## What Mundell says the first time each is smelled, in turn.
const SMELLS := [
	"SMELLS LIKE GUN OIL ROUND HERE...",
	"SOMETHIN' SHINY CLOSE BY. NEW IRON.",
	"GUN'S CLOSE. I CAN SMELL IT.",
]

## Where each gun seen or smelled lies (GunFinder.spot), and each he has said
## something about; the next look round (game clock).
var seen := {}
var told := {}
var next_look := 0.0
var said := 0


func id() -> String:
	return "new_iron"


func attach() -> void:
	if game.level != null and Campaign.ORDER.has(game.level.id):
		tick_with(_tick)


func save() -> Dictionary:
	if seen.is_empty():
		return {}
	var rows: Array = []
	for at: Vector2 in seen:
		rows.append([at.x, at.y])
	return {"seen": rows}


func restore(state: Dictionary) -> void:
	seen = {}
	told = {}
	for row: Variant in state.get("seen", []):
		var r: Array = row if row is Array else []
		if r.size() >= 2:
			var x: float = r[0]
			var y: float = r[1]
			seen[GunFinder.spot(x, y)] = true
			told[GunFinder.spot(x, y)] = true


## A few times a second: a gun the local player ain't got that they can see
## from `see_reach`, or smell from `smell_reach` (no sight needed), goes on the
## map; the first time one is smelled Mundell says so.
func _tick(_dt: float) -> void:
	if game.clock < next_look or game.players.is_empty():
		return
	next_look = game.clock + .25
	if not GunFinder.on(game):
		return
	var p := game.local_player
	if p.health <= 0:
		return
	var see := GunFinder.tuned("see_reach")
	var smell := GunFinder.tuned("smell_reach")
	for entry: Array in game.pickups:
		var item := str(entry[0])
		var x: float = entry[1]
		var y: float = entry[2]
		if absf(x - p.x) > see or absf(y - p.y) > see or not Weapons.NAMES.has(item):
			continue
		if not GunFinder.unclaimed(item, p.armory):
			continue
		var at := GunFinder.spot(x, y)
		var d := Vector2(x - p.x, y - p.y).length()
		var near := d <= smell and absf(GunFinder.lies(game, entry) - game.world.stand(p)) < 1.6
		if not seen.has(at):
			var eye := GunFinder.lies(game, entry) + .2
			if near or (d <= see and game.world.visible(p.x, p.y, x, y, p.eye, eye)):
				seen[at] = true
		if near and not told.has(at) and game.message_until <= game.clock:
			# Said in his voice (Barks "new_iron", mundell_new_iron_*); shown
			# on the message line when he can't (another player's view).
			if not game.barks.say(game, "new_iron", true):
				game.message(str(SMELLS[said % SMELLS.size()]), 2.6)
			said += 1
			_tell_near(p, smell)


## Every gun within smell of `p` counts as told: a row of them lying together
## is one line, not one each.
func _tell_near(p: Player, smell: float) -> void:
	for entry: Array in game.pickups:
		var x: float = entry[1]
		var y: float = entry[2]
		if Weapons.NAMES.has(str(entry[0])) and Vector2(x - p.x, y - p.y).length() <= smell:
			told[GunFinder.spot(x, y)] = true


func sprites() -> Array:
	var out: Array = []
	if not game.players.is_empty() and GunFinder.on(game):
		GunFinder.shines(game, out)
	return out


## The pools of light under the guns near `p` (view_lights.gd).
func lights(p: Player) -> Array:
	return GunFinder.lights(game, p) if GunFinder.on(game) else []


## Draws the seen guns on the open automap (game_automap.gd); whether any was.
func draw_map(c: Canvas, map: GameAutomap) -> bool:
	return GunFinder.draw_map(c, map, game, seen) if GunFinder.on(game) else false
