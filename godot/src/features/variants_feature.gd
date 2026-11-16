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

const RematchFeature := preload("res://src/features/boss_rematch.gd")

## Seconds a dropped door lies about.
const DOOR_LIE := 25.0
## What each chapter's tough guy says when he first sees the player, in his
## kind's bark voice (scripts/audio_spec.py TOUGH_SAYS, cues bark_<kind>).
const TOUGH_SAYS := {
	"tough_earl": "Big Earl runs this street, boy!",
	"tough_clem": "Step right up, boy! Clem's waitin'!",
	"tough_tom": "Timber, boy! That's you fallin'!",
	"tough_bubba": "Bubba's got a full head of steam!",
	"tough_chuck": "Dinner bell's ringin', and you're dinner!",
	"tough_pete": "Four tires and a grudge, boy!",
	"tough_zorgo": "Zorgo the Large demands your beer!",
}

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
	tick_with(_tick)
	if Variants.TOUGH.has(game.level.id):
		# The tough guy's walk while the level loads, not on the first tick.
		Variants.start_walk(game)


func _tick(_dt: float) -> void:
	if not swapped:
		swapped = true
		_swap()
	if told or tough == null:
		# Swapped, and the tough guy told of (or none): nothing more to tick.
		sleep()
		return
	if game.clock < .5:
		return
	var e := tough
	if not e.alive:
		told = true
	elif e.alerted and e.player_seen:
		told = true
		var def: Dictionary = Enemy.DEFS[e.kind]
		var line := str(def.get("tough_line", ""))
		var title := str(def["tough_title"])
		game.message(title + (" - " + line if line != "" else ""), 3.2)
		_says(e)


## The tough guy says his piece (TOUGH_SAYS, cue bark_<kind>) with CHATTER
## on, captioned; his kind's alert cry otherwise. Sound and caption only.
func _says(e: Enemy) -> void:
	var cue := "bark_" + e.kind
	var said := str(TOUGH_SAYS.get(e.kind, ""))
	if (
		said != ""
		and int(game.chatter) != CussLines.OFF
		and game.sound != null
		and game.sound.has(cue)
	):
		game.sound_at(cue, e.x, e.y, 1.0)
		game.caption = said
		game.caption_until = game.clock + 2.4
		return
	game.sound_at(str(Enemy.AWAKE.get(e.kind, "billy_alert")), e.x, e.y, 1.0)


## The chapter's tough guy among the enemies, or null.
func _find_tough() -> Enemy:
	for e: Enemy in game.enemies:
		var def: Dictionary = Enemy.DEFS[e.kind]
		if def.has("tough_for"):
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
			Variants.become(e, str(swaps[i]))
	var picked := Variants.tough_pick(game, swaps)
	if picked >= 0:
		tough = game.enemies[picked]
		Variants.become(tough, str(Variants.TOUGH[id_now]))


func _rematch() -> bool:
	var rematch: RematchFeature = game.features["boss_rematch"]
	return rematch.active


func door_left(e: Enemy) -> float:
	if not Variants.DOORS.has(e.kind):
		return 0.0
	var left: float = doors.get(e.get_instance_id(), Variants.DOORS[e.kind])
	return left


## The door takes `amount`; at nothing left it is knocked down.
func tear(e: Enemy, amount: float) -> void:
	var left := door_left(e) - amount
	doors[e.get_instance_id()] = maxf(0.0, left)
	if left > 0.0:
		return
	fallen.append([e.x + cos(e.angle) * .45, e.y + sin(e.angle) * .45, e.angle, game.clock])
	game.sound_at(ShipAliens.cue(game, "tailgate_clang", "ricochet"), e.x, e.y, 1.0)
	var floor_z: float = game.world.stand(e)
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
		var def: Dictionary = Enemy.DEFS[e.kind]
		if str(def.get("door_picture", "")) == "":
			continue
		if not game.in_view(e.x, e.y, 1.0):
			continue
		# Swung aside while he fires; held square in front of him otherwise.
		var aside: bool = e.windup > 0.0 or e.volley > 0
		var a := e.angle + (1.35 if aside else 0.0)
		var x := e.x + cos(a) * (e.radius + .1)
		var y := e.y + sin(a) * (e.radius + .1)
		var door := View.Sprite.new(
			x, y, Variants.DOOR_PICTURE, .82, game.world.elevation(x, y) + .1
		)
		door.plane = a - PI * .5
		out.append(door)
	var kept: Array = []
	for row: Array in fallen:
		var fell_at: float = row[3]
		if game.clock - fell_at > DOOR_LIE:
			continue
		kept.append(row)
		var rx: float = row[0]
		var ry: float = row[1]
		if not game.in_view(rx, ry, 1.0):
			continue
		var lying := View.Sprite.new(
			rx, ry, Variants.DOOR_PICTURE, .3, game.world.elevation(rx, ry)
		)
		var turn: float = row[2]
		lying.plane = turn - PI * .5
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
			var left: float = doors[e.get_instance_id()]
			torn[str(i)] = left
	return {"swapped": true, "doors": torn, "told": told}


## A save keeps every enemy's kind: nothing is swapped again. Each of the
## level's own whose saved kind is not the level's is set up as that kind.
func restore(state: Dictionary) -> void:
	swapped = true
	told = state.get("told", false)
	for i in game.enemy_ids.size():
		var e: Enemy = game.enemies[i]
		var placed_def: Dictionary = game.level.enemies[i]
		var placed := str(placed_def.get("kind", e.kind))
		if not Enemy.KINDS.has(e.kind):
			e.kind = placed
		if e.kind != placed:
			Variants.refresh(e)
	tough = _find_tough()
	var torn: Variant = state.get("doors", {})
	if torn is Dictionary:
		var torn_doors: Dictionary = torn
		for key: Variant in torn_doors:
			var i := int(str(key))
			if i >= 0 and i < game.enemies.size():
				var left: float = torn_doors[key]
				var holder: Enemy = game.enemies[i]
				doors[holder.get_instance_id()] = left
