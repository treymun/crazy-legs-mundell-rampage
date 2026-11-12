## Tougher hands and each chapter's tough guy (src/variants.gd). On a
## chapter's first tick some of the level's own regulars become variants
## (Variants.swaps: by difficulty and their place in the level, no dice) and
## one regular at a busy spot mid-chapter becomes the chapter's tough guy.
## A save keeps each enemy's kind, so a loaded game is never swapped again:
## restore() only sets each restored variant up as its kind. Here too the
## shield deputies' car doors (their hit points saved by enemy index), the
## door drawn in front of each, and the tough guy's name on the HUD the
## first time he sees the player.
extends GameFeature

## Seconds a dropped door lies about.
const DOOR_LIE := 25.0

var swapped := false
## Car doors' hit points, by enemy (instance id); an enemy not here has his whole.
var doors := {}
## Doors knocked down: [x, y, angle, when].
var fallen: Array = []
var told := false
var tough: Enemy = null
var shielded: Array = []
var look_again := 0.0
var looked_over := -1


func id() -> String:
	return "variants"


func attach() -> void:
	Variants.art = game.art
	Variants.paint_door(game.art)
	game.ticked.connect(_tick)


func _tick(_dt: float) -> void:
	if not swapped:
		swapped = true
		_swap()
	if told or tough == null or game.clock < .5:
		return
	var e := tough
	if not e.alive:
		told = true
	elif e.alerted and e.player_seen:
		told = true
		var line := String(Enemy.DEFS[e.kind].get("tough_line", ""))
		var title := String(Enemy.DEFS[e.kind]["tough_title"])
		game.message(title + (" - " + line if line != "" else ""), 3.2)
		game.sound_at(String(Enemy.AWAKE.get(e.kind, "billy_alert")), e.x, e.y, 1.0)


## The chapter's tough guy among the enemies, or null.
func _find_tough() -> Enemy:
	for e: Enemy in game.enemies:
		if Enemy.DEFS[e.kind].has("tough_for"):
			return e
	return null


func _swap() -> void:
	var id_now: String = game.level.id
	if id_now == "hub" or id_now == "range" or game.features.has("boss_rematch") and _rematch():
		return
	var kinds: Array = []
	for i in game.enemy_ids.size():
		kinds.append(game.enemies[i].kind)
	var swaps := Variants.swaps(id_now, kinds, game.difficulty)
	for i: int in swaps:
		var e: Enemy = game.enemies[i]
		if e.alive:
			Variants.become(e, String(swaps[i]))
	var picked := Variants.tough_pick(game, swaps)
	if picked >= 0:
		tough = game.enemies[picked]
		Variants.become(tough, String(Variants.TOUGH[id_now]))


func _rematch() -> bool:
	return bool(game.features["boss_rematch"].get("active"))


func door_left(e: Enemy) -> float:
	if not Variants.DOORS.has(e.kind):
		return 0.0
	return float(doors.get(e.get_instance_id(), Variants.DOORS[e.kind]))


## The door takes `amount`; at nothing left it is knocked down.
func tear(e: Enemy, amount: float) -> void:
	var left := door_left(e) - amount
	doors[e.get_instance_id()] = maxf(0.0, left)
	if left > 0.0:
		return
	fallen.append([e.x + cos(e.angle) * .45, e.y + sin(e.angle) * .45, e.angle, game.clock])
	game.sound_at(ShipAliens.cue(game, "tailgate_clang", "ricochet"), e.x, e.y, 1.0)
	var floor_z: float = game.world.elevation(e.x, e.y)
	game.burst(e.x + cos(e.angle) * .4, e.y + sin(e.angle) * .4, floor_z + .6, "spark", 12, 1.6)
	e.stun = maxf(e.stun, .5)
	e.flinch = maxf(e.flinch, .4)


func sprites() -> Array:
	var out: Array = []
	if game.clock >= look_again or game.enemies.size() != looked_over:
		# Who holds a door, looked for again now and then (one may be spawned).
		look_again = game.clock + 1.0
		looked_over = game.enemies.size()
		shielded.clear()
		for e: Enemy in game.enemies:
			if Variants.DOORS.has(e.kind):
				shielded.append(e)
	for e: Enemy in shielded:
		if not e.alive or not Variants.DOORS.has(e.kind) or door_left(e) <= 0.0:
			continue
		if String(Enemy.DEFS[e.kind].get("door_picture", "")) == "":
			continue
		if not game.in_view(e.x, e.y, 1.0):
			continue
		# Swung aside while he fires; held square in front of him otherwise.
		var aside: bool = e.windup > 0.0 or e.volley > 0
		var a := e.angle + (1.35 if aside else 0.0)
		var x := e.x + cos(a) * (e.radius + .1)
		var y := e.y + sin(a) * (e.radius + .1)
		var door := Renderer.Sprite.new(
			x, y, Variants.DOOR_PICTURE, .82, game.world.elevation(x, y) + .1
		)
		door.plane = a - PI * .5
		out.append(door)
	var kept: Array = []
	for row: Array in fallen:
		if game.clock - float(row[3]) > DOOR_LIE:
			continue
		kept.append(row)
		if not game.in_view(float(row[0]), float(row[1]), 1.0):
			continue
		var lying := Renderer.Sprite.new(
			float(row[0]),
			float(row[1]),
			Variants.DOOR_PICTURE,
			.3,
			game.world.elevation(float(row[0]), float(row[1]))
		)
		lying.plane = float(row[2]) - PI * .5
		out.append(lying)
	fallen = kept
	return out


func save() -> Dictionary:
	if not swapped:
		return {}
	var torn := {}
	for i in game.enemies.size():
		var e: Enemy = game.enemies[i]
		if doors.has(e.get_instance_id()):
			torn[str(i)] = float(doors[e.get_instance_id()])
	return {"swapped": true, "doors": torn, "told": told}


## A save keeps every enemy's kind: nothing is swapped again. Each of the
## level's own whose saved kind is not the level's is set up as that kind.
func restore(state: Dictionary) -> void:
	swapped = true
	told = bool(state.get("told", false))
	for i in game.enemy_ids.size():
		var e: Enemy = game.enemies[i]
		var placed := String(game.level.enemies[i].get("kind", e.kind))
		if not Enemy.KINDS.has(e.kind):
			e.kind = placed
		if e.kind != placed:
			Variants.refresh(e)
	tough = _find_tough()
	var torn = state.get("doors", {})
	if torn is Dictionary:
		for key in torn:
			var i := int(key)
			if i >= 0 and i < game.enemies.size():
				doors[game.enemies[i].get_instance_id()] = float(torn[key])
