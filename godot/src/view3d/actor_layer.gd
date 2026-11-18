## The enemies and bosses of the 3D view that have a rigged model
## (ActorModels): each sprite the game lists for an enemy (View.Sprite
## `who`) is drawn as that enemy's scene instead (ActorView,
## scenes/actors/<kind>.tscn), which poses itself from the sprite.
class_name ActorLayer3D
extends Node3D

## Ragdolls kept for bodies out of sight (the oldest let go first).
const KEEP_DOLLS := 64
## Models kept hidden (parked) when their body leaves the view, by body, at
## most PARK and `park_most` (the view's room in the shader instance buffer:
## a hidden model keeps its slot): a model made from its scene costs a few
## tenths of a millisecond, and bodies leave and come back into view all the
## time as the player turns (the view-bench made 1.6 a frame with the old
## pool of three a kind). A body coming back gets its own model, a new one
## the oldest parked model of its kind, else a new one; either is posed
## afresh (ActorView.revive), as a model just made.
const PARK := 24
## A living body further than ActorView.REACH and this from the eye (map
## x, y) is not posed or given a model at all: its model would not show
## (its parts end there, measured to their middle, which is nearer its feet
## than this). The game lists bodies to 54 cells ahead; their models were
## made and posed every frame to show nothing (pass 10). The dead are posed
## as before (their ragdolls).
const BEYOND := 5.0

var models: ActorModels
## enemy instance id -> ActorView
var _shown: Dictionary = {}
## enemy instance id -> the Ragdoll of a body out of sight
var _dolls: Dictionary = {}
## The player's reflection (only the mirror's camera sees it), or null.
var _mirrored: ActorView
## "enemy instance id:gear" -> the piece of gear shot off (show_gear)
var _pieces: Dictionary = {}
## enemy instance id -> its hidden ActorView, the oldest first (PARK)
var _parked: Dictionary = {}
var park_most := PARK
## Models made from their scenes since the layer was made (view_perf_check).
var made_total := 0


func _init(p_models: ActorModels) -> void:
	models = p_models


## Find the ragdoll rigs of the kinds among `enemies` now (a level's first
## frame) rather than at a first kill (a few hundredths of a second each).
func prepare(enemies: Array) -> void:
	# The last level's bodies lie there, not here.
	_dolls.clear()
	for e: Enemy in enemies:
		var kind := kind_of(e)
		if kind == "" or Enemy.BOSS_TITLES.has(e.kind) or RagdollRig.has(kind):
			continue
		var info: Dictionary = models.kinds[kind]
		var packed := models.scene(kind)
		if not info.get("ragdoll", true) or packed == null:
			continue
		var view := packed.instantiate()
		RagdollRig.of(kind, view, info)
		view.free()


## Load the models of `kinds` that may come later (a county event's hogs and
## raiders), make their looks and find their ragdoll rigs now (a level's
## first frame) rather than when the first of them comes into view.
func warm(kinds: Array) -> void:
	for kind: String in kinds:
		if not models.has(kind):
			continue
		models.material(kind)
		var packed := models.scene(kind)
		if packed == null:
			continue
		# The scene's first instance costs the most (as a prop's does).
		var view := packed.instantiate()
		var info: Dictionary = models.kinds[kind]
		if not RagdollRig.has(kind) and info.get("ragdoll", true):
			RagdollRig.of(kind, view, info)
		view.free()


## The models the layer holds, shown, parked, the mirror's and the gear shot
## off (each a slot in the shader instance buffer).
func held() -> int:
	return _shown.size() + _parked.size() + _pieces.size() + (1 if _mirrored != null else 0)


## How many models are parked (their bodies out of view).
func parked() -> int:
	return _parked.size()


## The materials the models shown now draw with (bodies, gear shot off,
## the player in the mirror; each once).
func live_materials() -> Array[ShaderMaterial]:
	var kinds := {}
	for view: ActorView in _shown.values():
		kinds[view.kind] = true
	if _mirrored != null:
		kinds[_mirrored.kind] = true
	var out: Array[ShaderMaterial] = []
	for kind: String in kinds:
		out.append(models.material(kind))
	for node: MeshInstance3D in _pieces.values():
		var m := node.material_override as ShaderMaterial
		if m != null and not out.has(m):
			out.append(m)
	return out


## The model kind an enemy is drawn with ("" when none).
func kind_of(e: Enemy) -> String:
	if models.has(e.kind):
		return e.kind
	var stem := Variants.stem(e.kind)
	return stem if models.has(stem) else ""


## Whether enemy `e`'s sprite `s` is drawn as its model. A kind whose body at
## rest is a build of its own that the model's parts cannot make (fit.json
## "down_cel": the derby champ's burnt-out wreck, the swamp king's sunk boat)
## keeps its cel for that.
func takes(s: View.Sprite, e: Enemy) -> bool:
	var kind := kind_of(e)
	if kind == "":
		return false
	var info: Dictionary = models.kinds[kind]
	var own_cel: bool = info.get("down_cel", false)
	if own_cel and ActorView.pose_of(s.image, Variants.stem(e.kind))[0] == "down":
		return false
	return true


## Show these sprites (each an enemy's, with a model) and no others. Returns
## the materials first used this frame (the view hands them its numbers).
func show_actors(
	sprites: Array,
	level: LevelData,
	clock: float,
	lost: Dictionary,
	gear_lost := {},
	eye := Vector3.INF
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	var most: int = Effects.RAGDOLL.get("budget", 40)
	# Fewer limb steps a frame on a low physics tier (src/core/quality.gd).
	Ragdoll.budget = Quality.steps(most)
	# The bodies about, so one lies on another (those out of sight lie still).
	var dolls: Array = _dolls.values()
	for id: int in _shown:
		var shown: ActorView = _shown[id]
		if shown.doll != null:
			dolls.append(shown.doll)
	Ragdoll.others = dolls
	var far := (ActorView.REACH + BEYOND) * (ActorView.REACH + BEYOND)
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		if e.alive and Vector2(s.x - eye.x, s.y - eye.y).length_squared() > far:
			continue
		var kind := kind_of(e)
		var id := e.get_instance_id()
		seen[id] = true
		var view: ActorView = _shown.get(id)
		if view == null or view.kind != kind:
			if view != null:
				_park(id, view)
			_shown.erase(id)
			view = _parked.get(id)
			if view != null and view.kind == kind:
				# Its own model, posed afresh as a model just made would be.
				_parked.erase(id)
				view.revive()
			else:
				view = _make(kind, fresh)
			if view == null:
				continue
			_shown[id] = view
			# A body back in sight lies as its ragdoll left it.
			if not e.alive:
				view.doll = _dolls.get(id)
			_dolls.erase(id)
		view.show_as(s, e, level, clock)
		var gone: Array = lost.get(e, [])
		view.lose(gone)
		var shed: Array = gear_lost.get(e, [])
		if not shed.is_empty():
			view.lose_gear(shed)
	for id: int in _shown.keys():
		if not seen.has(id):
			var old: ActorView = _shown[id]
			if old.doll != null:
				_dolls[id] = old.doll
				if _dolls.size() > KEEP_DOLLS:
					_dolls.erase(_dolls.keys()[0])
			_shown.erase(id)
			_park(id, old)
	while _parked.size() > maxi(0, park_most):
		var oldest: int = _parked.keys()[0]
		var gone: ActorView = _parked[oldest]
		_parked.erase(oldest)
		gone.queue_free()
	return fresh


## A model no longer shown: hidden and kept for its body (or the next of its
## kind); show_actors lets the oldest go past park_most.
func _park(id: int, view: ActorView) -> void:
	var was: ActorView = _parked.get(id)
	if was != null and was != view:
		was.queue_free()
	_parked.erase(id)
	view.retire()
	_parked[id] = view


## Show the player's reflection `s` as its model on render layers `bits`
## (the mirror's camera's alone), or none (null, or a body with no model).
## Returns the material when first used this frame.
func show_reflection(
	s: View.Sprite, level: LevelData, clock: float, bits: int
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var e: Enemy = null
	if s != null and s.who is Enemy:
		e = s.who as Enemy
	var kind := kind_of(e) if e != null else ""
	if kind == "" or (_mirrored != null and _mirrored.kind != kind):
		if _mirrored != null:
			_mirrored.queue_free()
			_mirrored = null
	if kind == "":
		return fresh
	if _mirrored == null:
		_mirrored = _make(kind, fresh, false)
		if _mirrored == null:
			return fresh
		_mirrored.set_layers(bits)
	_mirrored.show_as(s, e, level, clock)
	return fresh


## Show these sprites (View.Sprite.gear: a boss's gear shot off, flying or
## lying) as that gear's part of the boss's model, and no other such pieces.
## Returns the materials first used this frame.
func show_gear(sprites: Array, level: LevelData) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		var kind := kind_of(e)
		if kind == "":
			continue
		var key := "%d:%s" % [e.get_instance_id(), s.gear]
		seen[key] = true
		var node: MeshInstance3D = _pieces.get(key)
		if node == null:
			var made := models.gear_mesh(kind, s.gear)
			if made.is_empty():
				continue
			var had := models.materials().size()
			node = MeshInstance3D.new()
			node.mesh = made[0]
			node.material_override = models.material(kind)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 32.0
			if models.materials().size() > had:
				fresh.append(models.material(kind))
			add_child(node)
			_pieces[key] = node
		var info: Dictionary = models.kinds[kind]
		var canvas: Array = info.get("canvas", [1.0, e.height])
		var tall: float = canvas[1]
		var fit: float = info.get("scale", 1.0)
		var size := e.height * e.variant / maxf(.1, tall) * fit
		node.transform = Transform3D(
			SolidLayer3D.godot_basis(s.turn).scaled(Vector3.ONE * size), Vector3(s.x, s.z, s.y)
		)
		var c := level.cell(
			clampf(s.x, 0.0, level.width - .01), clampf(s.y, 0.0, level.height - .01)
		)
		var ti := clampi(level.area[c], 0, maxi(0, level.tints.size() / 3 - 1)) * 3
		var tone := Color(1, 1, 1, level.light[c])
		if level.tints.size() >= 3:
			tone = Color(level.tints[ti], level.tints[ti + 1], level.tints[ti + 2], level.light[c])
		node.set_instance_shader_parameter("tone", tone)
		node.set_instance_shader_parameter("look", e.boss_phase if e.boss_phase >= 2 else 0)
	for key: String in _pieces.keys():
		if not seen.has(key):
			var old: MeshInstance3D = _pieces[key]
			old.queue_free()
			_pieces.erase(key)
	return fresh


func _make(kind: String, fresh: Array[ShaderMaterial], reuse := true) -> ActorView:
	if reuse:
		for id: int in _parked:
			var again: ActorView = _parked[id]
			if again.kind == kind:
				_parked.erase(id)
				again.revive()
				return again
	var packed := models.scene(kind)
	if packed == null:
		return null
	var had := models.materials().size()
	var view := packed.instantiate() as ActorView
	if view == null:
		return null
	made_total += 1
	if not view.setup(models):
		view.free()
		return null
	if models.materials().size() > had:
		fresh.append(models.material(kind))
	add_child(view)
	return view
