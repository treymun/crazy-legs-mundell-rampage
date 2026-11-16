## HARD and HOG WILD bring a bigger posse: when a chapter starts, every fourth
## (HARD) or every second (HOG WILD) of the county's hands that is about from
## the start gets a partner of the same kind beside it. They join the enemies
## after the level's own (so a save's count of those still matches) and are
## saved here, in the save's features block, with every other enemy that
## joined after the level's own (a boss's backup, features/boss_fight.gd;
## Maw's pod crew).
extends GameFeature

const STEP := {2: 4, 3: 2}
## The fields of a partner kept in a save.
const KEPT := [
	"kind", "x", "y", "hp", "alerted", "angle", "dormant", "hunt_until", "died_at", "explosive"
]

## Room in total_kills for the enemies that join later. A save's kills are
## checked against total_kills before the features give those enemies back
## (session_store.gd counts them all once they are), so a new game leaves
## this much room until its first tick counts them exactly: a save made after
## killing a posse partner or a boss's backup never fails that check.
const ROOM := 400

var spawned := false


func id() -> String:
	return "posse"


func attach() -> void:
	if game.level.id != "hub":
		# The Crossroads never ticks its features and never keeps a count.
		game.total_kills += ROOM
	tick_with(_tick)


func _tick(_dt: float) -> void:
	# Its one tick's work done (now or before a save): nothing more to tick.
	sleep()
	if spawned:
		return
	spawned = true
	game.total_kills = 0
	for e: Enemy in game.enemies:
		if e.hostile:
			game.total_kills += 1
	var step: int = STEP.get(game.difficulty, 0)
	if step == 0:
		return
	var count := 0
	for i in game.enemy_ids.size():
		var anchor: Enemy = game.enemies[i]
		if not anchor.tactical() or anchor.dormant or not anchor.alive:
			continue
		count += 1
		if count % step != 0:
			continue
		var found: Variant = _beside(anchor)
		if found == null:
			continue
		var spot: Vector2 = found
		var partner := Enemy.new(anchor.kind, spot.x, spot.y, anchor.angle + .6)
		partner.flank = -anchor.flank
		game.enemies.append(partner)
		game.total_kills += 1


## An open spot a step from `anchor` a body fits in, or null.
func _beside(anchor: Enemy) -> Variant:
	for reach: float in [1.1, 1.6, 2.2]:
		for k in 8:
			var a := k * TAU / 8.0 + .4
			var x := anchor.x + cos(a) * reach
			var y := anchor.y + sin(a) * reach
			if not game.world.blocked(x, y, anchor.radius + .05):
				return Vector2(x, y)
	return null


func save() -> Dictionary:
	if not spawned:
		return {}
	var rows: Array = []
	for i in range(game.enemy_ids.size(), game.enemies.size()):
		var e: Enemy = game.enemies[i]
		var row := {}
		for key: String in KEPT:
			row[key] = e.get(key)
		rows.append(row)
	return {"spawned": true, "partners": rows}


func restore(state: Dictionary) -> void:
	var was_spawned: bool = state.get("spawned", false)
	if not was_spawned:
		return
	spawned = true
	for item: Variant in state.get("partners", []):
		if not item is Dictionary:
			continue
		var row: Dictionary = item
		if not Enemy.DEFS.has(str(row.get("kind", ""))):
			continue
		var row_x: float = row["x"]
		var row_y: float = row["y"]
		var e := Enemy.new(str(row["kind"]), row_x, row_y)
		for key: String in KEPT:
			if row.has(key) and key != "kind":
				e.set(key, row[key])
		game.enemies.append(e)
