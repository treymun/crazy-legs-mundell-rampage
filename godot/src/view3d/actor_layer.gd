## The enemies and bosses of the 3D view that have a rigged model
## (ActorModels): each sprite the game lists for an enemy (View.Sprite
## `who`) is drawn as that enemy's scene instead (ActorView,
## scenes/actors/<kind>.tscn), which poses itself from the sprite.
class_name ActorLayer3D
extends Node3D

## Ragdolls kept for bodies out of sight (the oldest let go first).
const KEEP_DOLLS := 64

var models: ActorModels
## enemy instance id -> ActorView
var _shown: Dictionary = {}
## enemy instance id -> the Ragdoll of a body out of sight
var _dolls: Dictionary = {}
## The player's reflection (only the mirror's camera sees it), or null.
var _mirrored: ActorView


func _init(p_models: ActorModels) -> void:
	models = p_models


## Find the ragdoll rigs of the kinds among `enemies` now (a level's first
## frame) rather than at a first kill (a few hundredths of a second each).
func prepare(enemies: Array) -> void:
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
	sprites: Array, level: LevelData, clock: float, lost: Dictionary
) -> Array[ShaderMaterial]:
	var fresh: Array[ShaderMaterial] = []
	var seen := {}
	var most: int = Effects.RAGDOLL.get("budget", 40)
	# TODO(merge, track I): scale by the physics tier, e.g.
	# `most = Quality.steps(most)` (src/core/quality.gd), and on Quality.physics
	# 0 maybe View.ragdolls off; that file is not on this branch.
	Ragdoll.budget = most
	for s: View.Sprite in sprites:
		var e := s.who as Enemy
		var kind := kind_of(e)
		var id := e.get_instance_id()
		seen[id] = true
		var view: ActorView = _shown.get(id)
		if view == null or view.kind != kind:
			if view != null:
				view.queue_free()
			_shown.erase(id)
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
	for id: int in _shown.keys():
		if not seen.has(id):
			var old: ActorView = _shown[id]
			if old.doll != null:
				_dolls[id] = old.doll
				if _dolls.size() > KEEP_DOLLS:
					_dolls.erase(_dolls.keys()[0])
			old.queue_free()
			_shown.erase(id)
	return fresh


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
		_mirrored = _make(kind, fresh)
		if _mirrored == null:
			return fresh
		_mirrored.set_layers(bits)
	_mirrored.show_as(s, e, level, clock)
	return fresh


func _make(kind: String, fresh: Array[ShaderMaterial]) -> ActorView:
	var packed := models.scene(kind)
	if packed == null:
		return null
	var had := models.materials().size()
	var view := packed.instantiate() as ActorView
	if view == null:
		return null
	if not view.setup(models):
		view.free()
		return null
	if models.materials().size() > had:
		fresh.append(models.material(kind))
	add_child(view)
	return view
